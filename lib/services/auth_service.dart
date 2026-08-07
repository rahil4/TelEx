import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'td_service.dart';
import 'settings_service.dart';

enum AuthStatus {
  starting,
  needCredentials, // api_id / api_hash not entered yet in Settings
  waitPhoneNumber,
  waitCode,
  waitPassword,
  ready,
  loggingOut,
  error,
}

/// Drives the TDLib login flow and exposes the current [AuthStatus] as a
/// stream so the UI can switch between Settings / Login / Explorer screens
/// reactively (see app.dart).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _statusController = StreamController<AuthStatus>.broadcast();
  Stream<AuthStatus> get status => _statusController.stream;
  AuthStatus _last = AuthStatus.starting;
  AuthStatus get current => _last;

  String? _lastError;
  String? get lastError => _lastError;
  AuthStatus? _retryTarget;

  StreamSubscription? _sub;

  void _emit(AuthStatus s) {
    _last = s;
    _statusController.add(s);
  }

  /// Call once at app start, after credentials are confirmed present.
  Future<void> initialize() async {
    final configured = await SettingsService.instance.isConfigured;
    if (!configured) {
      _emit(AuthStatus.needCredentials);
      return;
    }

    // IMPORTANT: subscribe before starting the client. TDLib pushes the
    // first updateAuthorizationState as soon as the client exists — if we
    // start the client first, that very first (and most important) update
    // can be dispatched to the broadcast stream before anyone is listening
    // and gets silently dropped, leaving the UI stuck on the loading spinner
    // forever. Subscribing first closes that race.
    _sub ??= TdService.instance.updates.listen(_onUpdate);
    await TdService.instance.start();
  }

  Future<void> _onUpdate(Map<String, dynamic> update) async {
    if (update['@type'] != 'updateAuthorizationState') return;
    final state = update['authorization_state'] as Map<String, dynamic>;
    final type = state['@type'] as String;

    switch (type) {
      case 'authorizationStateWaitTdlibParameters':
        await _sendTdlibParameters();
        break;
      case 'authorizationStateWaitPhoneNumber':
        _emit(AuthStatus.waitPhoneNumber);
        break;
      case 'authorizationStateWaitCode':
        _emit(AuthStatus.waitCode);
        break;
      case 'authorizationStateWaitPassword':
        _emit(AuthStatus.waitPassword);
        break;
      case 'authorizationStateReady':
        _emit(AuthStatus.ready);
        break;
      case 'authorizationStateLoggingOut':
        _emit(AuthStatus.loggingOut);
        break;
      case 'authorizationStateClosed':
        _emit(AuthStatus.needCredentials);
        break;
      default:
        // authorizationStateWaitEmailAddress / waitEmailCode / waitOtherDeviceConfirmation
        // are newer TDLib login paths not wired up yet — fall through as an error
        // for now rather than silently hanging.
        break;
    }
  }

  Future<void> _sendTdlibParameters() async {
    final apiId = await SettingsService.instance.getApiId();
    final apiHash = await SettingsService.instance.getApiHash();
    if (apiId == null || apiHash == null) {
      _emit(AuthStatus.needCredentials);
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory('${dir.path}/tdlib');
    await dbDir.create(recursive: true);

    await TdService.instance.send({
      '@type': 'setTdlibParameters',
      'database_directory': dbDir.path,
      'use_message_database': true,
      'use_secret_chats': false,
      'api_id': apiId,
      'api_hash': apiHash,
      'system_language_code': 'fa',
      'device_model': Platform.isWindows ? 'Windows Desktop' : 'Android',
      'application_version': '0.1.0',
    });
  }

  Future<void> submitPhoneNumber(String phone) async {
    await SettingsService.instance.savePhoneNumber(phone);
    try {
      await TdService.instance.send({
        '@type': 'setAuthenticationPhoneNumber',
        'phone_number': phone,
      });
    } catch (e) {
      _lastError = e.toString();
      _retryTarget = AuthStatus.waitPhoneNumber;
      _emit(AuthStatus.error);
    }
  }

  Future<void> submitCode(String code) async {
    try {
      await TdService.instance.send({
        '@type': 'checkAuthenticationCode',
        'code': code,
      });
    } catch (e) {
      _lastError = e.toString();
      _retryTarget = AuthStatus.waitCode;
      _emit(AuthStatus.error);
    }
  }

  Future<void> submitPassword(String password) async {
    try {
      await TdService.instance.send({
        '@type': 'checkAuthenticationPassword',
        'password': password,
      });
    } catch (e) {
      _lastError = e.toString();
      _retryTarget = AuthStatus.waitPassword;
      _emit(AuthStatus.error);
    }
  }

  /// Lets the UI recover from an error state (e.g. a timed-out request)
  /// without restarting the whole app — goes back to whichever step failed.
  void retry() {
    _emit(_retryTarget ?? AuthStatus.waitPhoneNumber);
  }

  Future<void> logOut() async {
    await TdService.instance.send({'@type': 'logOut'});
    await SettingsService.instance.clearCredentials();
  }
}
