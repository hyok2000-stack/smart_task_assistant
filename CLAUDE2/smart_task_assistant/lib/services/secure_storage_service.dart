import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _passwordKey = 'backend.password';

  // AI API Key 在 SecureStorage 中的键名（不再明文存入 SharedPreferences）
  static const _aiApiKeyKey = 'ai.apiKey';
  static const _aiChatApiKeyKey = 'ai.chatAPIKey';

  // 迁移标记：旧版本曾把 apiKey 明文写入 SharedPreferences 的这些键
  static const _legacyAiApiKeyPrefsKey = 'apiKey';
  static const _legacyChatApiKeyPrefsKey = 'chatAPIKey';

  FlutterSecureStorage? _storage;
  final Map<String, String> _memoryStore = {};

  /// 迁移是否已完成的标记（存于 SharedPreferences）
  static const _migrationDoneKey = 'ai_apikey_migrated_v1';

  /// 懒初始化 FlutterSecureStorage。
  ///
  /// 注意：关闭 encryptedSharedPreferences。该选项在部分 Android 设备上会触发
  /// 原生层 Keystore 异常（绕过 Dart try-catch 直接崩溃，见 flutter_secure_storage
  /// issue #480/#547）。默认模式仍使用 Android Keystore 加密，足够安全。
  FlutterSecureStorage? _tryCreateStorage() {
    try {
      return const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: false),
      );
    } catch (_) {
      return null;
    }
  }

  /// 最近一次写入是否降级到了纯内存（Keystore/SecureStorage 不可用）。
  /// 降级意味着数据只存活于当前进程——UI 层可据此提示用户。
  bool lastWriteDegraded = false;

  Future<String?> read(String key) async {
    if (kIsWeb) return _memoryStore[key];
    try {
      _storage ??= _tryCreateStorage();
      if (_storage == null) return _memoryStore[key];
      return await _storage!.read(key: key);
    } catch (_) {
      return _memoryStore[key];
    }
  }

  Future<void> write(String key, String value) async {
    if (kIsWeb) {
      _memoryStore[key] = value;
      return;
    }
    lastWriteDegraded = false;
    try {
      _storage ??= _tryCreateStorage();
      if (_storage == null) {
        lastWriteDegraded = true;
        _memoryStore[key] = value;
        debugPrint('SecureStorage 不可用，写入已降级为进程内存（重启丢失）');
        return;
      }
      await _storage!.write(key: key, value: value);
    } catch (_) {
      lastWriteDegraded = true;
      _memoryStore[key] = value;
      debugPrint('SecureStorage 写入异常，已降级为进程内存（重启丢失）');
    }
  }

  Future<void> delete(String key) async {
    if (kIsWeb) {
      _memoryStore.remove(key);
      return;
    }
    try {
      _storage ??= _tryCreateStorage();
      if (_storage == null) {
        _memoryStore.remove(key);
        return;
      }
      await _storage!.delete(key: key);
    } catch (_) {
      _memoryStore.remove(key);
    }
  }

  Future<String?> readPassword() => read(_passwordKey);

  Future<void> writePassword(String password) => write(_passwordKey, password);

  Future<void> deletePassword() => delete(_passwordKey);

  // ---- 后端 auth token ----
  static const _backendTokenKey = 'backend.token';

  Future<String?> readBackendToken() => read(_backendTokenKey);

  Future<void> writeBackendToken(String token) => write(_backendTokenKey, token);

  Future<void> deleteBackendToken() => delete(_backendTokenKey);

  // ---- AI API Key ----

  Future<String?> readAiApiKey() => read(_aiApiKeyKey);

  Future<void> writeAiApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      await delete(_aiApiKeyKey);
      return;
    }
    await write(_aiApiKeyKey, apiKey);
  }

  Future<String?> readAiChatApiKey() => read(_aiChatApiKeyKey);

  Future<void> writeAiChatApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      await delete(_aiChatApiKeyKey);
      return;
    }
    await write(_aiChatApiKeyKey, apiKey);
  }

  /// 一次性迁移：把旧版本明文存于 SharedPreferences 的 AI API Key 迁移到
  /// SecureStorage，并清除明文残留。幂等，多次调用安全。
  ///
  /// 应在应用启动早期调用一次。
  Future<void> migrateApiKeysIfNeeded() async {
    if (kIsWeb) return; // Web 无 SecureStorage，跳过
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationDoneKey) == true) return;

      // 迁移 apiKey
      final legacyApiKey =
          prefs.getString(_legacyAiApiKeyPrefsKey);
      if (legacyApiKey != null && legacyApiKey.isNotEmpty) {
        final existing = await read(_aiApiKeyKey);
        if (existing == null || existing.isEmpty) {
          await write(_aiApiKeyKey, legacyApiKey);
          debugPrint('[SecureStorage] 已迁移 AI apiKey 到安全存储');
        }
        await prefs.remove(_legacyAiApiKeyPrefsKey);
      }

      // 迁移 chatAPIKey
      final legacyChatKey =
          prefs.getString(_legacyChatApiKeyPrefsKey);
      if (legacyChatKey != null && legacyChatKey.isNotEmpty) {
        final existing = await read(_aiChatApiKeyKey);
        if (existing == null || existing.isEmpty) {
          await write(_aiChatApiKeyKey, legacyChatKey);
          debugPrint('[SecureStorage] 已迁移 AI chatAPIKey 到安全存储');
        }
        await prefs.remove(_legacyChatApiKeyPrefsKey);
      }

      await prefs.setBool(_migrationDoneKey, true);
    } catch (e) {
      debugPrint('[SecureStorage] 迁移 AI API Key 失败: $e');
    }
  }
}
