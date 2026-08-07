import 'dart:async';
import 'package:libtdjson/client.dart';

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
      final result = _client!.receive(1.0);
      if (result != null) {
        _handleIncoming(result);
      } else {
        // no data within timeout — yield back to the event loop briefly
        await Future.delayed(const Duration(milliseconds: 1));
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

  /// Sends a request and resolves with the matching reply.
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
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(extra);
        throw TimeoutException('پاسخی از تلگرام دریافت نشد: ${request['@type']}');
      },
    );
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
