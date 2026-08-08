import 'dart:async';
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
/// TDLib's JSON API is a single request/response channel: you `send()` a
/// JSON object and, separately, `receive()` JSON objects back — replies to
/// your own requests AND unsolicited "update*" events (new messages, auth
/// state changes, etc.) come back on the same channel. We tell them apart
/// using the `@extra` field: every request we send gets a unique `@extra`
/// value, and if a received object carries that same value back, it's the
/// reply to that specific call; otherwise it's an update we publish on
/// [updates] for whoever is interested (AuthService, ManifestService, ...).
///
/// NOTE: `receive()` is a blocking native call with a timeout. Polling it in
/// a tight loop on the UI isolate (as done below, for simplicity) is fine to
/// get the app running, but for a smooth production build this loop should
/// move to its own Isolate. Left as a clearly-marked follow-up.
class TdService {
  TdService._();
  static final TdService instance = TdService._();

  Client? _client;
  bool _running = false;
  int _extraCounter = 0;

  final _updatesController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updatesController.stream;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  bool get isStarted => _client != null;

  Future<void> start() async {
    if (_client != null) return;
    _client = Client()..create();
    _running = true;
    unawaited(_receiveLoop());
  }

  Future<void> _receiveLoop() async {
    while (_running && _client != null) {
      // receive() blocks the isolate synchronously while it waits, so we
      // keep the native timeout short (rather than the original 1s) and
      // explicitly yield every iteration — this keeps the UI responsive
      // between polls without needing a separate Isolate. A real Isolate
      // split would remove the stutter entirely; noted as a follow-up.
      final result = _client!.receive(0.1);
      if (result != null) {
        _handleIncoming(result);
      }
      await Future.delayed(Duration.zero);
    }
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
    if (_client == null) {
      throw StateError('TdService.start() must be called first');
    }
    final extra = 'req_${_extraCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final withExtra = {...request, '@extra': extra};
    final completer = Completer<Map<String, dynamic>>();
    _pending[extra] = completer;
    _client!.send(withExtra);
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
    if (_client == null) return;
    _client!.send(request);
  }

  void dispose() {
    _running = false;
    _updatesController.close();
    _pending.clear();
  }
}
