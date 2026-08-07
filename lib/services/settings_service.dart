import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the person's own Telegram API credentials (api_id / api_hash),
/// obtained for free and per-account from https://my.telegram.org.
///
/// These are entered from the app's Settings screen — nothing is bundled
/// or hard-coded into the app itself, per the requirement that connection
/// settings live inside the app.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  final _storage = const FlutterSecureStorage();

  static const _kApiId = 'telegram_api_id';
  static const _kApiHash = 'telegram_api_hash';
  static const _kPhoneNumber = 'telegram_phone_number';

  Future<int?> getApiId() async {
    final v = await _storage.read(key: _kApiId);
    return v == null ? null : int.tryParse(v);
  }

  Future<String?> getApiHash() => _storage.read(key: _kApiHash);

  Future<String?> getPhoneNumber() => _storage.read(key: _kPhoneNumber);

  Future<void> savePhoneNumber(String phone) =>
      _storage.write(key: _kPhoneNumber, value: phone);

  Future<void> saveCredentials({required int apiId, required String apiHash}) async {
    await _storage.write(key: _kApiId, value: apiId.toString());
    await _storage.write(key: _kApiHash, value: apiHash);
  }

  Future<bool> get isConfigured async {
    final id = await getApiId();
    final hash = await getApiHash();
    return id != null && hash != null && hash.isNotEmpty;
  }

  /// Clears stored credentials — used from Settings > "قطع اتصال".
  /// Does not touch the TDLib session database itself; call
  /// TdService.instance.logOut() first if a full sign-out is wanted.
  Future<void> clearCredentials() async {
    await _storage.delete(key: _kApiId);
    await _storage.delete(key: _kApiHash);
    await _storage.delete(key: _kPhoneNumber);
  }
}
