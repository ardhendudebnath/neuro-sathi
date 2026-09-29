import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore-backed storage for the access token and the database key.
class SecureStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<String?> token() => _storage.read(key: 'access_token');
  Future<void> setToken(String value) => _storage.write(key: 'access_token', value: value);
  Future<void> clearToken() => _storage.delete(key: 'access_token');

  Future<String?> dbKey() => _storage.read(key: 'db_key');
  Future<void> setDbKey(String value) => _storage.write(key: 'db_key', value: value);
}
