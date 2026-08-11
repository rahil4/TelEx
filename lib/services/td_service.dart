import 'dart:async';
import 'dart:convert';
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
/// IMPORTANT: this was briefly moved to run inside a background Isolate for
/// performance, then reverted — Flutter plugins (which is how libtdjson
/// ships its Android native library) generally only initialize correctly on
/// the main isolate; creating the Client on a background Isolate risked
/// silently hanging there instead, which broke the whole app (Settings
/// screen never completed). Kept on the main isolate for correctness; the
/// polling below is tuned to minimize UI jank instead.
///
/// TDLib's JSON API is a single request/response channel: you `send()` a
/// JSON object and, separately, `receive()` JSON objects back — replies to
/// your own requests AND unsolicited "update*" events (new messages, auth
/// state changes, etc.) come back on the same channel. We tell them apart
/// using the `@extra` field: every request we send gets a unique `@extra`
/// value, and if a received object carries that same value back, it's the
/// reply to that specific call; otherwise it's an update we publish on
/// [updates] for whoever is interested (AuthService, ManifestService, ...).
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
      // receive() blocks synchronously while it waits. Keeping the native
      // timeout short and adding a small idle delay (only when nothing was
      // received) gives the UI isolate real breathing room between polls,
      // at the cost of a little latency on incoming updates — a reasonable
      // trade-off for a personal-use app without a working Isolate split.
      final result = _client!.receive(0.05);
      if (result != null) {
        _handleIncoming(result);
      } else {
        await Future.delayed(const Duration(milliseconds: 30));
      }
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
        String payload;
        try {
          payload = jsonEncode(request);
        } catch (_) {
          payload = '(قابل نمایش نیست)';
        }
        if (payload.length > 300) payload = '${payload.substring(0, 300)}…';
        throw TdError(
          code: (result['code'] as num?)?.toInt() ?? 0,
          message: '${result['message'] as String? ?? 'خطای نامشخص از تلگرام'} | درخواست: $payload',
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
