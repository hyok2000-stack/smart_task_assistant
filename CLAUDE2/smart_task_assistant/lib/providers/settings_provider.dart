import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// AI服务模式枚举
enum AIMode { local, localLLM, remoteAPI }

/// 智答AI服务模式枚举
enum ChatAIMode { localLLM, remoteAPI }

/// 设置提供者 - 管理主题、语言等全局设置
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('zh', 'CN');
  bool _clipboardMonitorEnabled = true; // 默认开启
  bool _notificationsEnabled = true;
  bool _reminderEnabled = true;
  int _reminderMinutes = 30;

  // AI服务配置
  AIMode _aiMode = AIMode.remoteAPI;
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

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get clipboardMonitorEnabled => _clipboardMonitorEnabled;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get reminderEnabled => _reminderEnabled;
  int get reminderMinutes => _reminderMinutes;

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

  /// 从存储加载设置
  Future<void> loadSettings() async {
    if (kIsWeb) {
      _loadFromWeb();
    } else {
      await _loadFromNative();
    }
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
    } catch (e) {
      debugPrint('加载设置失败: $e');
    }
  }

  Future<void> _loadFromNative() async {
    // 原生平台暂时使用默认值
    // 后续可以使用 shared_preferences
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    if (kIsWeb) {
      _saveToWeb();
    }
    // 原生平台保存逻辑
  }

  void _saveToWeb() {
    _setWebStorage('themeMode', _themeMode.toString());
    _setWebStorage('language', _locale.languageCode);
    _setWebStorage(
        'clipboardMonitorEnabled', _clipboardMonitorEnabled.toString());
    _setWebStorage('notificationsEnabled', _notificationsEnabled.toString());
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

  // Web 存储辅助方法
  String? _getWebStorage(String key) {
    if (kIsWeb) {
      // 使用 dart:html 实现
      try {
        final storage = _getWebStorageImpl();
        return storage[key];
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  void _setWebStorage(String key, String value) {
    if (kIsWeb) {
      try {
        final storage = _getWebStorageImpl();
        storage[key] = value;
      } catch (e) {
        debugPrint('保存设置失败: $e');
      }
    }
  }

  dynamic _getWebStorageImpl() {
    // 使用动态调用避免编译错误
    return null; // 实际实现在 web 平台
  }
}
