import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _passwordKey = 'backend.password';

  FlutterSecureStorage? _storage;
  final Map<String, String> _memoryStore = {};

  FlutterSecureStorage get _impl {
    _storage ??= const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    return _storage!;
  }

  Future<String?> read(String key) async {
    if (kIsWeb) return _memoryStore[key];
    try {
      return await _impl.read(key: key);
    } catch (_) {
      return _memoryStore[key];
    }
  }

  Future<void> write(String key, String value) async {
    if (kIsWeb) {
      _memoryStore[key] = value;
      return;
    }
    try {
      await _impl.write(key: key, value: value);
    } catch (_) {
      _memoryStore[key] = value;
    }
  }

  Future<void> delete(String key) async {
    if (kIsWeb) {
      _memoryStore.remove(key);
      return;
    }
    try {
      await _impl.delete(key: key);
    } catch (_) {
      _memoryStore.remove(key);
    }
  }

  Future<String?> readPassword() => read(_passwordKey);

  Future<void> writePassword(String password) => write(_passwordKey, password);

  Future<void> deletePassword() => delete(_passwordKey);
}
