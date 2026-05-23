import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'noir.sessionToken';
  static const _userKey = 'noir.user';
  static const _vaultKey = 'noir.vault';

  Future<void> saveSession(
      {required String token, required Map<String, dynamic> user}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveVault(Map<String, dynamic> vault) async {
    await _storage.write(key: _vaultKey, value: jsonEncode(vault));
  }

  Future<Map<String, dynamic>?> readVault() async {
    final raw = await _storage.read(key: _vaultKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _vaultKey);
  }

  Future<String?> readString(String key) => _storage.read(key: key);

  Future<void> writeString(String key, String value) =>
      _storage.write(key: key, value: value);
}
