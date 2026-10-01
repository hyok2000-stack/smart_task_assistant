import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 条件导入：Web平台使用 html 库
import '../utils/platform_stub.dart'
    if (dart.library.html) '../utils/platform_web.dart';
import '../services/ai_service.dart';
import '../services/secure_storage_service.dart';

/// AI服务模式枚举
enum AIMode { local, localLLM, remoteAPI }

/// 智答AI服务模式枚举
enum ChatAIMode { localLLM, remoteAPI }

/// 设置提供者 - 管理主题、语言等全局设置
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('zh', 'CN');
  bool _clipboardMonitorEnabled = false; // 默认关闭：涉及隐私，需用户主动开启
  bool _notificationsEnabled = true;
  bool _reminderEnabled = true;
  int _reminderMinutes = 30;
  bool _reminderSoundEnabled = true;
  bool _reminderVibrationEnabled = true;
  bool _quietHoursEnabled = false;
  int _quietHoursStart = 22;
  int _quietHoursEnd = 7;
  bool _taskReminderSoundEnabled = true;
  bool _taskReminderVibrationEnabled = true;
  bool _habitReminderSoundEnabled = true;
  bool _habitReminderVibrationEnabled = true;
  bool _autoCompleteParentTask = true;
  double _ttsVolume = 0.9; // 默认音量较高 (0.0-1.0)

  // AI服务配置
  AIMode _aiMode = AIMode.local;
  String _localLLMAddress = 'http://localhost:11434';
  String _localLLMModel = 'qwen2.5:7b';
  String _apiServiceName = 'OpenAI';
  String _apiKey = '';
  String _apiBase = 'https://api.openai.com/v1';
  String _apiModel = 'gpt-3.5-turbo';

  // 智答AI配置
  ChatAIMode _chatMode = ChatAIMode.remoteAPI;
  String _chatLocalLLMAddress = 'http://localhost:11434';
  String _chatLocalLLMModel = 'qwen2.5:7b';
  String _chatAPIServiceName = 'OpenAI';
  String _chatAPIKey = '';
  String _chatAPIBase = 'https://api.openai.com/v1';
  String _chatAPIModel = 'gpt-3.5-turbo';

  // 版本信息
  String _appVersion = '1.0.0';

  // Getters
  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get clipboardMonitorEnabled => _clipboardMonitorEnabled;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get reminderEnabled => _reminderEnabled;
  int get reminderMinutes => _reminderMinutes;
  bool get reminderSoundEnabled => _reminderSoundEnabled;
  bool get reminderVibrationEnabled => _reminderVibrationEnabled;
  bool get quietHoursEnabled => _quietHoursEnabled;
  int get quietHoursStart => _quietHoursStart;
  int get quietHoursEnd => _quietHoursEnd;
  bool get taskReminderSoundEnabled => _taskReminderSoundEnabled;
  bool get taskReminderVibrationEnabled => _taskReminderVibrationEnabled;
  bool get habitReminderSoundEnabled => _habitReminderSoundEnabled;
  bool get habitReminderVibrationEnabled => _habitReminderVibrationEnabled;
  bool get autoCompleteParentTask => _autoCompleteParentTask;

  bool isQuietTime(DateTime time) {
    if (!_quietHoursEnabled) return false;
    if (_quietHoursStart == _quietHoursEnd) return true;
    if (_quietHoursStart < _quietHoursEnd) {
      return time.hour >= _quietHoursStart && time.hour < _quietHoursEnd;
    }
    return time.hour >= _quietHoursStart || time.hour < _quietHoursEnd;
  }

  double get ttsVolume => _ttsVolume;

  // AI服务getter
  AIMode get aiMode => _aiMode;
  String get localLLMAddress => _localLLMAddress;
  String get localLLMModel => _localLLMModel;
  String get apiServiceName => _apiServiceName;
  String get apiKey => _apiKey;
  String get apiBase => _apiBase;
  String get apiModel => _apiModel;

  // 智答AI getter
  ChatAIMode get chatMode => _chatMode;
  String get chatLocalLLMAddress => _chatLocalLLMAddress;
  String get chatLocalLLMModel => _chatLocalLLMModel;
  String get chatAPIServiceName => _chatAPIServiceName;
  String get chatAPIKey => _chatAPIKey;
  String get chatAPIBase => _chatAPIBase;
  String get chatAPIModel => _chatAPIModel;

  // 别名，兼容settings_screen.dart
  bool get clipboardMonitor => _clipboardMonitorEnabled;
  bool get reminderEnabledGetter => _reminderEnabled;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isZh => _locale.languageCode == 'zh';

  /// 获取应用版本号
  String get appVersion => _appVersion;

  /// 从存储加载设置（Web/原生统一走键值适配器，序列化逻辑只写一份）
  Future<void> loadSettings() async {
    try {
      final prefs = kIsWeb ? null : await SharedPreferences.getInstance();
      _loadFromStore(_createStore(prefs));
      if (!kIsWeb) {
        // 安全改进：API Key 从 SecureStorage 读取（旧版本会先迁移）
        await SecureStorageService.instance.migrateApiKeysIfNeeded();
        _apiKey =
            await SecureStorageService.instance.readAiApiKey() ?? _apiKey;
        _chatAPIKey =
            await SecureStorageService.instance.readAiChatApiKey() ??
                _chatAPIKey;
      }
      await _loadAppVersion();
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
    notifyListeners();
  }

  /// 统一的设置加载（键不存在时保持当前值 = 字段默认值，
  /// Web 与原生行为从此一致，不再各自漂移）
  void _loadFromStore(_SettingsKV kv) {
    final themeModeStr = kv.getString('themeMode');
    if (themeModeStr != null) {
      _themeMode = ThemeMode.values
          .firstWhere((m) => m.toString() == themeModeStr, orElse: () => _themeMode);
    }

    final languageCode = kv.getString('language');
    if (languageCode != null) {
      _locale = Locale(languageCode, languageCode == 'zh' ? 'CN' : 'US');
    }

    // 剪贴板监视（默认关闭：涉及隐私，需用户主动开启）
    _clipboardMonitorEnabled =
        kv.getBool('clipboardMonitorEnabled') ?? _clipboardMonitorEnabled;
    _notificationsEnabled =
        kv.getBool('notificationsEnabled') ?? _notificationsEnabled;
    _reminderSoundEnabled =
        kv.getBool('reminderSoundEnabled') ?? _reminderSoundEnabled;
    _reminderVibrationEnabled =
        kv.getBool('reminderVibrationEnabled') ?? _reminderVibrationEnabled;
    _quietHoursEnabled = kv.getBool('quietHoursEnabled') ?? _quietHoursEnabled;
    _quietHoursStart = kv.getInt('quietHoursStart') ?? _quietHoursStart;
    _quietHoursEnd = kv.getInt('quietHoursEnd') ?? _quietHoursEnd;
    _taskReminderSoundEnabled =
        kv.getBool('taskReminderSoundEnabled') ?? _taskReminderSoundEnabled;
    _taskReminderVibrationEnabled = kv.getBool('taskReminderVibrationEnabled') ??
        _taskReminderVibrationEnabled;
    _habitReminderSoundEnabled =
        kv.getBool('habitReminderSoundEnabled') ?? _habitReminderSoundEnabled;
    _habitReminderVibrationEnabled = kv.getBool('habitReminderVibrationEnabled') ??
        _habitReminderVibrationEnabled;
    _autoCompleteParentTask =
        kv.getBool('autoCompleteParentTask') ?? _autoCompleteParentTask;
    _ttsVolume = kv.getDouble('ttsVolume') ?? _ttsVolume;

    // AI 配置（apiKey 在原生端由 SecureStorage 覆盖，见 loadSettings）
    final aiModeStr = kv.getString('aiMode');
    if (aiModeStr != null) {
      _aiMode = AIMode.values
          .firstWhere((m) => m.toString() == aiModeStr, orElse: () => _aiMode);
    }
    _localLLMAddress = kv.getString('localLLMAddress') ?? _localLLMAddress;
    _localLLMModel = kv.getString('localLLMModel') ?? _localLLMModel;
    _apiServiceName = kv.getString('apiServiceName') ?? _apiServiceName;
    _apiKey = kv.getString('apiKey') ?? _apiKey;
    _apiBase = kv.getString('apiBase') ?? _apiBase;
    _apiModel = kv.getString('apiModel') ?? _apiModel;

    // 智答AI配置
    final chatModeStr = kv.getString('chatMode');
    if (chatModeStr != null) {
      _chatMode = ChatAIMode.values.firstWhere(
          (m) => m.toString() == chatModeStr,
          orElse: () => _chatMode);
    }
    _chatLocalLLMAddress =
        kv.getString('chatLocalLLMAddress') ?? _chatLocalLLMAddress;
    _chatLocalLLMModel =
        kv.getString('chatLocalLLMModel') ?? _chatLocalLLMModel;
    _chatAPIServiceName =
        kv.getString('chatAPIServiceName') ?? _chatAPIServiceName;
    _chatAPIKey = kv.getString('chatAPIKey') ?? _chatAPIKey;
    _chatAPIBase = kv.getString('chatAPIBase') ?? _chatAPIBase;
    _chatAPIModel = kv.getString('chatAPIModel') ?? _chatAPIModel;
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (e) {
      debugPrint('获取应用版本失败: $e');
    }
  }

  /// 保存设置（Web/原生统一走键值适配器）
  Future<void> _saveSettings() async {
    try {
      final prefs = kIsWeb ? null : await SharedPreferences.getInstance();
      _saveToStore(_createStore(prefs), includeApiKeys: kIsWeb);
      if (!kIsWeb) {
        // 安全改进：API Key 不入 SharedPreferences，走 SecureStorage
        await SecureStorageService.instance.writeAiApiKey(_apiKey);
        await SecureStorageService.instance.writeAiChatApiKey(_chatAPIKey);
      }
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  /// 统一的设置保存（includeApiKeys 仅 Web 为 true——原生端 Key 走 SecureStorage）
  void _saveToStore(_SettingsKV kv, {required bool includeApiKeys}) {
    kv.setString('themeMode', _themeMode.toString());
    kv.setString('language', _locale.languageCode);
    kv.setBool('clipboardMonitorEnabled', _clipboardMonitorEnabled);
    kv.setBool('notificationsEnabled', _notificationsEnabled);
    kv.setBool('reminderSoundEnabled', _reminderSoundEnabled);
    kv.setBool('reminderVibrationEnabled', _reminderVibrationEnabled);
    kv.setBool('quietHoursEnabled', _quietHoursEnabled);
    kv.setInt('quietHoursStart', _quietHoursStart);
    kv.setInt('quietHoursEnd', _quietHoursEnd);
    kv.setBool('taskReminderSoundEnabled', _taskReminderSoundEnabled);
    kv.setBool('taskReminderVibrationEnabled', _taskReminderVibrationEnabled);
    kv.setBool('habitReminderSoundEnabled', _habitReminderSoundEnabled);
    kv.setBool('habitReminderVibrationEnabled', _habitReminderVibrationEnabled);
    kv.setBool('autoCompleteParentTask', _autoCompleteParentTask);
    kv.setDouble('ttsVolume', _ttsVolume);

    kv.setString('aiMode', _aiMode.toString());
    kv.setString('localLLMAddress', _localLLMAddress);
    kv.setString('localLLMModel', _localLLMModel);
    kv.setString('apiServiceName', _apiServiceName);
    if (includeApiKeys) kv.setString('apiKey', _apiKey);
    kv.setString('apiBase', _apiBase);
    kv.setString('apiModel', _apiModel);

    kv.setString('chatMode', _chatMode.toString());
    kv.setString('chatLocalLLMAddress', _chatLocalLLMAddress);
    kv.setString('chatLocalLLMModel', _chatLocalLLMModel);
    kv.setString('chatAPIServiceName', _chatAPIServiceName);
    if (includeApiKeys) kv.setString('chatAPIKey', _chatAPIKey);
    kv.setString('chatAPIBase', _chatAPIBase);
    kv.setString('chatAPIModel', _chatAPIModel);
  }

  /// 创建当前平台的键值存储适配器
  static _SettingsKV _createStore(SharedPreferences? prefs) =>
      prefs == null ? _WebKV() : _PrefsKV(prefs);

  /// 上次保存时 API Key 是否因 SecureStorage 不可用而只存于进程内存
  /// （重启即丢）。UI 层可读取此标志提示用户。
  bool get aiKeyDegradedToMemory =>
      !kIsWeb && SecureStorageService.instance.lastWriteDegraded;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  /// 切换深色模式
  void toggleDarkMode(bool value) {
    _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    _saveSettings();
    notifyListeners();
  }

  /// 设置语言
  void setLocale(Locale locale) {
    _locale = locale;
    _saveSettings();
    notifyListeners();
  }

  /// 设置剪贴板监视
  void setClipboardMonitorEnabled(bool value) {
    _clipboardMonitorEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置通知
  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置提醒启用
  void setReminderEnabled(bool value) {
    _reminderEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置提醒分钟数
  void setReminderMinutes(int value) {
    _reminderMinutes = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置提醒声音
  void setReminderSoundEnabled(bool value) {
    _reminderSoundEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置提醒振动
  void setReminderVibrationEnabled(bool value) {
    _reminderVibrationEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setQuietHoursEnabled(bool value) {
    _quietHoursEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setQuietHours({required int startHour, required int endHour}) {
    _quietHoursStart = startHour.clamp(0, 23);
    _quietHoursEnd = endHour.clamp(0, 23);
    _saveSettings();
    notifyListeners();
  }

  void setTaskReminderSoundEnabled(bool value) {
    _taskReminderSoundEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setTaskReminderVibrationEnabled(bool value) {
    _taskReminderVibrationEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setHabitReminderSoundEnabled(bool value) {
    _habitReminderSoundEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setHabitReminderVibrationEnabled(bool value) {
    _habitReminderVibrationEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setAutoCompleteParentTask(bool value) {
    _autoCompleteParentTask = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置TTS音量
  void setTtsVolume(double value) {
    _ttsVolume = value.clamp(0.0, 1.0);
    _saveSettings();
    notifyListeners();
  }

  /// 设置AI模式
  void setAIMode(AIMode value) {
    _aiMode = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置本地LLM地址
  void setLocalLLMAddress(String value) {
    _localLLMAddress = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置本地LLM模型
  void setLocalLLMModel(String value) {
    _localLLMModel = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置API服务名称
  void setAPIServiceName(String value) {
    _apiServiceName = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置API密钥
  void setAPIKey(String value) {
    _apiKey = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置API地址
  void setAPIBase(String value) {
    _apiBase = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置API模型
  void setAPIModel(String value) {
    _apiModel = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答AI模式
  void setChatMode(ChatAIMode value) {
    _chatMode = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答本地LLM地址
  void setChatLocalLLMAddress(String value) {
    _chatLocalLLMAddress = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答本地LLM模型
  void setChatLocalLLMModel(String value) {
    _chatLocalLLMModel = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答API服务名称
  void setChatAPIServiceName(String value) {
    _chatAPIServiceName = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答API密钥
  void setChatAPIKey(String value) {
    _chatAPIKey = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答API地址
  void setChatAPIBase(String value) {
    _chatAPIBase = value;
    _saveSettings();
    notifyListeners();
  }

  /// 设置智答API模型
  void setChatAPIModel(String value) {
    _chatAPIModel = value;
    _saveSettings();
    notifyListeners();
  }

  /// 兼容方法 - 设置剪贴板监听
  void setClipboardMonitor(bool value) {
    setClipboardMonitorEnabled(value);
  }

  /// 重置为默认设置
  Future<void> resetToDefault() async {
    _themeMode = ThemeMode.system;
    _locale = const Locale('zh', 'CN');
    _clipboardMonitorEnabled = true;
    _notificationsEnabled = true;
    _reminderEnabled = true;
    _reminderMinutes = 30;
    _reminderSoundEnabled = true;
    _reminderVibrationEnabled = true;
    _ttsVolume = 0.9;

    _aiMode = AIMode.local;
    _localLLMAddress = 'http://localhost:11434';
    _localLLMModel = 'qwen2.5:7b';
    _apiServiceName = 'OpenAI';
    _apiKey = '';
    _apiBase = 'https://api.openai.com/v1';
    _apiModel = 'gpt-3.5-turbo';

    _chatMode = ChatAIMode.remoteAPI;
    _chatLocalLLMAddress = 'http://localhost:11434';
    _chatLocalLLMModel = 'qwen2.5:7b';
    _chatAPIServiceName = 'OpenAI';
    _chatAPIKey = '';
    _chatAPIBase = 'https://api.openai.com/v1';
    _chatAPIModel = 'gpt-3.5-turbo';

    await _saveSettings();
    notifyListeners();
  }

  /// 验证URL格式
  bool isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 验证模型名称
  bool isValidModelName(String modelName) {
    return modelName.isNotEmpty && modelName.trim().isNotEmpty;
  }

  /// 同步 AI 配置到 AIService
  Future<void> syncAIConfig() async {
    final aiService = AIService();
    await aiService.loadConfig();

    String provider;
    String baseUrl;
    String apiKey;
    String model;
    bool enabled;

    switch (_aiMode) {
      case AIMode.local:
        provider = 'local';
        baseUrl = '';
        apiKey = '';
        model = '';
        enabled = false;
        break;
      case AIMode.localLLM:
        provider = 'ollama';
        baseUrl = _localLLMAddress;
        apiKey = '';
        model = _localLLMModel;
        enabled = true;
        break;
      case AIMode.remoteAPI:
        provider = _apiServiceName.toLowerCase();
        baseUrl = _apiBase;
        apiKey = _apiKey;
        model = _apiModel;
        enabled = true;
        break;
    }

    final newConfig = AIConfig(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      enabled: enabled,
    );

    await aiService.updateConfig(newConfig);

    // 通知监听器，刷新界面显示的当前模型信息
    notifyListeners();
  }

  /// 获取当前使用的 AI 模型显示名称
  String getCurrentAIModelName() {
    final aiService = AIService();
    return aiService.currentModelDisplayName;
  }
}

/// 设置键值存储适配器：屏蔽 Web(localStorage 字符串) 与
/// 原生(SharedPreferences 强类型)的差异，序列化逻辑只写一份。
abstract class _SettingsKV {
  String? getString(String key);
  bool? getBool(String key);
  int? getInt(String key);
  double? getDouble(String key);
  void setString(String key, String value);
  void setBool(String key, bool value);
  void setInt(String key, int value);
  void setDouble(String key, double value);
}

/// 原生平台：SharedPreferences 强类型包装
class _PrefsKV implements _SettingsKV {
  _PrefsKV(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  int? getInt(String key) => _prefs.getInt(key);
  @override
  double? getDouble(String key) => _prefs.getDouble(key);
  @override
  void setString(String key, String value) => _prefs.setString(key, value);
  @override
  void setBool(String key, bool value) => _prefs.setBool(key, value);
  @override
  void setInt(String key, int value) => _prefs.setInt(key, value);
  @override
  void setDouble(String key, double value) => _prefs.setDouble(key, value);
}

/// Web 平台：localStorage 全为字符串，读侧按需解析
class _WebKV implements _SettingsKV {
  @override
  String? getString(String key) => getWebStorage(key);
  @override
  bool? getBool(String key) {
    final v = getWebStorage(key);
    return v == null ? null : v == 'true';
  }

  @override
  int? getInt(String key) {
    final v = getWebStorage(key);
    return v == null ? null : int.tryParse(v);
  }

  @override
  double? getDouble(String key) {
    final v = getWebStorage(key);
    return v == null ? null : double.tryParse(v);
  }

  @override
  void setString(String key, String value) => setWebStorage(key, value);
  @override
  void setBool(String key, bool value) =>
      setWebStorage(key, value.toString());
  @override
  void setInt(String key, int value) => setWebStorage(key, value.toString());
  @override
  void setDouble(String key, double value) =>
      setWebStorage(key, value.toString());
}
