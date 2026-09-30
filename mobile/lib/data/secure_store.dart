import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore-backed storage for the session tokens and the database key.
class SecureStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static const _access = 'access_token';
  static const _accessExpires = 'access_expires_at';
  static const _refresh = 'refresh_token';

  /// The short-lived access token.
  Future<String?> token() => _storage.read(key: _access);

  Future<DateTime?> accessExpiresAt() async => DateTime.tryParse(await _storage.read(key: _accessExpires) ?? '');

  /// The long-lived token used to renew the access token.
  Future<String?> refreshToken() => _storage.read(key: _refresh);

  /// Called on each renewal (by the app or the background sync worker).
  Future<void> saveAccess(String token, DateTime expiresAt) async {
    await _storage.write(key: _access, value: token);
    await _storage.write(key: _accessExpires, value: expiresAt.toUtc().toIso8601String());
  }

  Future<void> saveSession({required String access, required DateTime expiresAt, String? refresh}) async {
    await saveAccess(access, expiresAt);
    if (refresh == null) {
      await _storage.delete(key: _refresh);
    } else {
      await _storage.write(key: _refresh, value: refresh);
    }
  }

  /// Forgets the session (signed out, or the server ended it). The database key stays.
  Future<void> clearSession() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _accessExpires);
    await _storage.delete(key: _refresh);
  }

  Future<String?> dbKey() => _storage.read(key: 'db_key');
  Future<void> setDbKey(String value) => _storage.write(key: 'db_key', value: value);
}
