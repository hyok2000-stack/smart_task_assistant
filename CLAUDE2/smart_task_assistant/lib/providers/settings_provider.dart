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

  /// 从存储加载设置
  Future<void> loadSettings() async {
    if (kIsWeb) {
      _loadFromWeb();
    } else {
      await _loadFromNative();
    }
    await _loadAppVersion();
    notifyListeners();
  }

  void _loadFromWeb() {
    // Web 平台从 localStorage 加载
    try {
      final themeModeStr = _getWebStorage('themeMode');
      if (themeModeStr != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.toString() == themeModeStr,
          orElse: () => ThemeMode.system,
        );
      }

      final languageCode = _getWebStorage('language');
      if (languageCode != null) {
        _locale = Locale(languageCode, languageCode == 'zh' ? 'CN' : 'US');
      }

      final clipboardEnabled = _getWebStorage('clipboardMonitorEnabled');
      if (clipboardEnabled != null) {
        _clipboardMonitorEnabled = clipboardEnabled == 'true';
      }

      final notificationsEnabled = _getWebStorage('notificationsEnabled');
      if (notificationsEnabled != null) {
        _notificationsEnabled = notificationsEnabled == 'true';
      }
      _autoCompleteParentTask =
          _getWebStorage('autoCompleteParentTask') != 'false';

      // 加载AI配置
      final aiModeStr = _getWebStorage('aiMode');
      if (aiModeStr != null) {
        _aiMode = AIMode.values.firstWhere(
          (m) => m.toString() == aiModeStr,
          orElse: () => AIMode.local,
        );
      }

      final localLLMAddress = _getWebStorage('localLLMAddress');
      if (localLLMAddress != null) {
        _localLLMAddress = localLLMAddress;
      }

      final localLLMModel = _getWebStorage('localLLMModel');
      if (localLLMModel != null) {
        _localLLMModel = localLLMModel;
      }

      final apiServiceName = _getWebStorage('apiServiceName');
      if (apiServiceName != null) {
        _apiServiceName = apiServiceName;
      }

      final apiKey = _getWebStorage('apiKey');
      if (apiKey != null) {
        _apiKey = apiKey;
      }

      final apiBase = _getWebStorage('apiBase');
      if (apiBase != null) {
        _apiBase = apiBase;
      }

      final apiModel = _getWebStorage('apiModel');
      if (apiModel != null) {
        _apiModel = apiModel;
      }

      // 加载ChatAI配置
      final chatModeStr = _getWebStorage('chatMode');
      if (chatModeStr != null) {
        _chatMode = ChatAIMode.values.firstWhere(
          (m) => m.toString() == chatModeStr,
          orElse: () => ChatAIMode.remoteAPI,
        );
      }

      final chatLocalLLMAddress = _getWebStorage('chatLocalLLMAddress');
      if (chatLocalLLMAddress != null) {
        _chatLocalLLMAddress = chatLocalLLMAddress;
      }

      final chatLocalLLMModel = _getWebStorage('chatLocalLLMModel');
      if (chatLocalLLMModel != null) {
        _chatLocalLLMModel = chatLocalLLMModel;
      }

      final chatAPIServiceName = _getWebStorage('chatAPIServiceName');
      if (chatAPIServiceName != null) {
        _chatAPIServiceName = chatAPIServiceName;
      }

      final chatAPIKey = _getWebStorage('chatAPIKey');
      if (chatAPIKey != null) {
        _chatAPIKey = chatAPIKey;
      }

      final chatAPIBase = _getWebStorage('chatAPIBase');
      if (chatAPIBase != null) {
        _chatAPIBase = chatAPIBase;
      }

      final chatAPIModel = _getWebStorage('chatAPIModel');
      if (chatAPIModel != null) {
        _chatAPIModel = chatAPIModel;
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> _loadFromNative() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载主题模式
      final themeModeStr = prefs.getString('themeMode');
      if (themeModeStr != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.toString() == themeModeStr,
          orElse: () => ThemeMode.system,
        );
      }

      // 加载语言
      final languageCode = prefs.getString('language');
      if (languageCode != null) {
        _locale = Locale(languageCode, languageCode == 'zh' ? 'CN' : 'US');
      }

      // 加载剪贴板监视（默认关闭：涉及隐私，需用户主动开启）
      _clipboardMonitorEnabled =
          prefs.getBool('clipboardMonitorEnabled') ?? false;

      // 加载通知设置
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;

      _reminderSoundEnabled = prefs.getBool('reminderSoundEnabled') ?? true;
      _reminderVibrationEnabled =
          prefs.getBool('reminderVibrationEnabled') ?? true;
      _quietHoursEnabled = prefs.getBool('quietHoursEnabled') ?? false;
      _quietHoursStart = prefs.getInt('quietHoursStart') ?? 22;
      _quietHoursEnd = prefs.getInt('quietHoursEnd') ?? 7;
      _taskReminderSoundEnabled =
          prefs.getBool('taskReminderSoundEnabled') ?? true;
      _taskReminderVibrationEnabled =
          prefs.getBool('taskReminderVibrationEnabled') ?? true;
      _habitReminderSoundEnabled =
          prefs.getBool('habitReminderSoundEnabled') ?? true;
      _habitReminderVibrationEnabled =
          prefs.getBool('habitReminderVibrationEnabled') ?? true;
      _autoCompleteParentTask = prefs.getBool('autoCompleteParentTask') ?? true;
      _ttsVolume = prefs.getDouble('ttsVolume') ?? 0.9;

      // 加载AI配置
      final aiModeStr = prefs.getString('aiMode');
      if (aiModeStr != null) {
        _aiMode = AIMode.values.firstWhere(
          (m) => m.toString() == aiModeStr,
          orElse: () => AIMode.local,
        );
      }

      _localLLMAddress =
          prefs.getString('localLLMAddress') ?? 'http://localhost:11434';
      _localLLMModel = prefs.getString('localLLMModel') ?? 'qwen2.5:7b';
      _apiServiceName = prefs.getString('apiServiceName') ?? 'OpenAI';
      // 安全改进：API Key 从 SecureStorage 读取（旧版本会先迁移）
      await SecureStorageService.instance.migrateApiKeysIfNeeded();
      _apiKey = await SecureStorageService.instance.readAiApiKey() ?? '';
      _apiBase = prefs.getString('apiBase') ?? 'https://api.openai.com/v1';
      _apiModel = prefs.getString('apiModel') ?? 'gpt-3.5-turbo';

      // 加载ChatAI配置
      final chatModeStr = prefs.getString('chatMode');
      if (chatModeStr != null) {
        _chatMode = ChatAIMode.values.firstWhere(
          (m) => m.toString() == chatModeStr,
          orElse: () => ChatAIMode.remoteAPI,
        );
      }

      _chatLocalLLMAddress =
          prefs.getString('chatLocalLLMAddress') ?? 'http://localhost:11434';
      _chatLocalLLMModel = prefs.getString('chatLocalLLMModel') ?? 'qwen2.5:7b';
      _chatAPIServiceName = prefs.getString('chatAPIServiceName') ?? 'OpenAI';
      // 安全改进：Chat API Key 从 SecureStorage 读取（旧版本会先迁移）
      _chatAPIKey =
          await SecureStorageService.instance.readAiChatApiKey() ?? '';
      _chatAPIBase =
          prefs.getString('chatAPIBase') ?? 'https://api.openai.com/v1';
      _chatAPIModel = prefs.getString('chatAPIModel') ?? 'gpt-3.5-turbo';
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (e) {
      debugPrint('获取应用版本失败: $e');
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    try {
      if (kIsWeb) {
        _saveToWeb();
      } else {
        await _saveToNative();
      }
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  void _saveToWeb() {
    _setWebStorage('themeMode', _themeMode.toString());
    _setWebStorage('language', _locale.languageCode);
    _setWebStorage(
      'clipboardMonitorEnabled',
      _clipboardMonitorEnabled.toString(),
    );
    _setWebStorage('notificationsEnabled', _notificationsEnabled.toString());
    _setWebStorage(
        'autoCompleteParentTask', _autoCompleteParentTask.toString());

    // 保存AI配置
    _setWebStorage('aiMode', _aiMode.toString());
    _setWebStorage('localLLMAddress', _localLLMAddress);
    _setWebStorage('localLLMModel', _localLLMModel);
    _setWebStorage('apiServiceName', _apiServiceName);
    _setWebStorage('apiKey', _apiKey);
    _setWebStorage('apiBase', _apiBase);
    _setWebStorage('apiModel', _apiModel);

    // 保存ChatAI配置
    _setWebStorage('chatMode', _chatMode.toString());
    _setWebStorage('chatLocalLLMAddress', _chatLocalLLMAddress);
    _setWebStorage('chatLocalLLMModel', _chatLocalLLMModel);
    _setWebStorage('chatAPIServiceName', _chatAPIServiceName);
    _setWebStorage('chatAPIKey', _chatAPIKey);
    _setWebStorage('chatAPIBase', _chatAPIBase);
    _setWebStorage('chatAPIModel', _chatAPIModel);
  }

  Future<void> _saveToNative() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('themeMode', _themeMode.toString());
      await prefs.setString('language', _locale.languageCode);
      await prefs.setBool('clipboardMonitorEnabled', _clipboardMonitorEnabled);
      await prefs.setBool('notificationsEnabled', _notificationsEnabled);

      await prefs.setBool('reminderSoundEnabled', _reminderSoundEnabled);
      await prefs.setBool(
          'reminderVibrationEnabled', _reminderVibrationEnabled);
      await prefs.setBool('quietHoursEnabled', _quietHoursEnabled);
      await prefs.setInt('quietHoursStart', _quietHoursStart);
      await prefs.setInt('quietHoursEnd', _quietHoursEnd);
      await prefs.setBool(
          'taskReminderSoundEnabled', _taskReminderSoundEnabled);
      await prefs.setBool(
          'taskReminderVibrationEnabled', _taskReminderVibrationEnabled);
      await prefs.setBool(
          'habitReminderSoundEnabled', _habitReminderSoundEnabled);
      await prefs.setBool(
          'habitReminderVibrationEnabled', _habitReminderVibrationEnabled);
      await prefs.setBool('autoCompleteParentTask', _autoCompleteParentTask);
      await prefs.setDouble('ttsVolume', _ttsVolume);

      await prefs.setString('aiMode', _aiMode.toString());
      await prefs.setString('localLLMAddress', _localLLMAddress);
      await prefs.setString('localLLMModel', _localLLMModel);
      await prefs.setString('apiServiceName', _apiServiceName);
      // 安全改进：API Key 不再明文存入 SharedPreferences，改走 SecureStorage
      await SecureStorageService.instance.writeAiApiKey(_apiKey);
      await prefs.setString('apiBase', _apiBase);
      await prefs.setString('apiModel', _apiModel);

      await prefs.setString('chatMode', _chatMode.toString());
      await prefs.setString('chatLocalLLMAddress', _chatLocalLLMAddress);
      await prefs.setString('chatLocalLLMModel', _chatLocalLLMModel);
      await prefs.setString('chatAPIServiceName', _chatAPIServiceName);
      await SecureStorageService.instance.writeAiChatApiKey(_chatAPIKey);
      await prefs.setString('chatAPIBase', _chatAPIBase);
      await prefs.setString('chatAPIModel', _chatAPIModel);
    } catch (e) {
      debugPrint('保存设置失败: $e');
    }
  }

  /// 设置主题模式
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

  // Web 存储辅助方法
  String? _getWebStorage(String key) {
    if (kIsWeb) {
      return getWebStorage(key);
    }
    return null;
  }

  void _setWebStorage(String key, String value) {
    if (kIsWeb) {
      setWebStorage(key, value);
    }
  }
}
