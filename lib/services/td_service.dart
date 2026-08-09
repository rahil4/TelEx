import 'dart:async';
import 'dart:isolate';
import 'package:libtdjson/client.dart';

/// TDLib's own error shape, surfaced as a proper Dart exception instead of
/// being mistaken for a normal (if empty-looking) response.
class TdError implements Exception {
  final int code;
  final String message;
  final String? requestType;
  TdError({required this.code, required this.message, this.requestType});

  @override
  String toString() =>
      'TdError($code${requestType != null ? ' از $requestType' : ''}): $message';
}

/// Thin, general-purpose wrapper around TDLib's JSON interface.
///
/// TDLib's client itself runs entirely inside a background [Isolate] — the
/// blocking, synchronous receive() call never touches the UI isolate, so
/// the interface stays responsive no matter how busy TDLib is. Requests go
/// out and responses/updates come back over a normal Isolate SendPort,
/// which Dart can transfer directly (our messages are always plain
/// String/num/bool/List/Map — no manual JSON encoding needed).
///
/// Replies to our own requests and unsolicited "update*" events (new
/// messages, auth state changes, etc.) share the same channel; we tell them
/// apart with an `@extra` field on every request, matched against the reply.
class TdService {
  TdService._();
  static final TdService instance = TdService._();

  Isolate? _isolate;
  SendPort? _isolateSendPort;
  Completer<void>? _ready;
  int _extraCounter = 0;

  final _updatesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updatesController.stream;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  bool get isStarted => _isolate != null;

  Future<void> start() async {
    if (_isolate != null) return;
    _ready = Completer<void>();

    final mainPort = ReceivePort();
    mainPort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      } else if (message is Map) {
        _handleIncoming(Map<String, dynamic>.from(message));
      }
    });

    _isolate = await Isolate.spawn(_tdIsolateEntry, mainPort.sendPort);
    await _ready!.future;
  }

  void _handleIncoming(Map<String, dynamic> result) {
    final extra = result['@extra'] as String?;
    if (extra != null) {
      final completer = _pending.remove(extra);
      if (completer != null) {
        completer.complete(result);
        return;
      }
    }
    _updatesController.add(result);
  }

  /// Sends a request and resolves with the matching reply. Throws a
  /// [TdError] if TDLib replies with an `{"@type":"error", ...}` object —
  /// without this check, callers that only look for a specific expected
  /// field (like `messages`) would silently treat an error response as
  /// "empty result" instead of surfacing what actually went wrong.
  Future<Map<String, dynamic>> send(Map<String, dynamic> request) {
    if (_isolateSendPort == null) {
      throw StateError('TdService.start() must be called first');
    }
    final extra = 'req_${_extraCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final withExtra = {...request, '@extra': extra};
    final completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    _isolateSendPort!.send(withExtra);
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(extra);
        throw TimeoutException('پاسخی از تلگرام دریافت نشد: ${request['@type']}');
      },
    ).then((result) {
      if (result['@type'] == 'error') {
        throw TdError(
          code: (result['code'] as num?)?.toInt() ?? 0,
          message: result['message'] as String? ?? 'خطای نامشخص از تلگرام',
          requestType: request['@type'] as String?,
        );
      }
      return result;
    });
  }

  /// Fire-and-forget variant for requests whose reply we don't care about
  /// waiting for synchronously (still resolved through the normal channel,
  /// any @extra mismatch is simply ignored).
  void sendNoWait(Map<String, dynamic> request) {
    _isolateSendPort?.send(request);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _updatesController.close();
    _pending.clear();
  }
}

/// Entry point run on the background isolate. Owns the TDLib [Client] for
/// its entire lifetime — creation, the blocking receive loop, and outgoing
/// sends all happen here, never on the UI isolate.
void _tdIsolateEntry(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  final client = Client()..create();
  var running = true;

  commandPort.listen((message) {
    if (message is Map) {
      client.send(Map<String, dynamic>.from(message));
    } else if (message == '__stop__') {
      running = false;
    }
  });

  Future<void> loop() async {
    while (running) {
      // Blocking is fine here — this isolate has nothing else to do.
      final result = client.receive(1.0);
      if (result != null) {
        mainSendPort.send(result);
      }
    }
  }

  loop();
}
