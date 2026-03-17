import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/task_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/reminder_service.dart';
import 'services/clipboard_monitor_service.dart';
import 'widgets/quick_add_modal.dart';
import 'utils/app_localizations.dart';
import 'database/database_helper.dart';

// 全局导航键，用于提醒服务显示弹窗
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 全局设置状态
class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light; // 强制使用浅色主题
  Locale _locale = const Locale('zh', 'CN');
  bool _clipboardMonitorEnabled = true; // 默认开启
  bool _notificationsEnabled = true;

  @override
  void notifyListeners() {
    super.notifyListeners();
    // 确保主题模式始终为浅色
    if (_themeMode != ThemeMode.light) {
      _themeMode = ThemeMode.light;
    }
  }

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;
  bool get clipboardMonitorEnabled => _clipboardMonitorEnabled;
  bool get notificationsEnabled => _notificationsEnabled;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isZh => _locale.languageCode == 'zh';

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void toggleDarkMode(bool value) {
    _themeMode = value ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }

  void setClipboardMonitorEnabled(bool value) {
    _clipboardMonitorEnabled = value;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }
}

// 全局设置实例
final AppSettings appSettings = AppSettings();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 创建 Provider 实例
  final taskProvider = TaskProvider();
  final settingsProvider = SettingsProvider();

  // 初始化提醒服务
  final reminderService = ReminderService();

  runApp(MyApp(
    taskProvider: taskProvider,
    settingsProvider: settingsProvider,
    reminderService: reminderService,
  ));
}

class MyApp extends StatefulWidget {
  final TaskProvider taskProvider;
  final SettingsProvider settingsProvider;
  final ReminderService reminderService;

  const MyApp({
    super.key,
    required this.taskProvider,
    required this.settingsProvider,
    required this.reminderService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('===== 应用生命周期状态改变: $state =====');

    switch (state) {
      case AppLifecycleState.resumed:
        // 应用从后台恢复
        debugPrint('应用恢复，重置数据库连接并重新加载数据...');
        _reloadDataWithReset();
        break;
      case AppLifecycleState.paused:
        // 应用进入后台
        debugPrint('应用进入后台');
        break;
      case AppLifecycleState.detached:
        // 应用即将被终止 - 重置所有单例连接
        debugPrint('应用即将被终止，重置所有单例连接');
        _resetAllConnections();
        break;
      case AppLifecycleState.inactive:
        // 应用处于非活动状态
        debugPrint('应用处于非活动状态');
        break;
      case AppLifecycleState.hidden:
        // 应用被隐藏
        debugPrint('应用被隐藏');
        break;
    }
  }

  /// 重置所有单例连接（数据库、存储服务等）
  Future<void> _resetAllConnections() async {
    try {
      debugPrint('===== _resetAllConnections 开始 =====');

      // 重置数据库连接
      final dbHelper = DatabaseHelper();
      await dbHelper.resetConnection();
      debugPrint('数据库连接已重置');

      debugPrint('===== _resetAllConnections 完成 =====');
    } catch (e) {
      debugPrint('重置连接失败: $e');
    }
  }

  /// 重新加载数据，并强制重置数据库连接
  Future<void> _reloadDataWithReset() async {
    debugPrint('开始重新加载数据（强制重置数据库连接）');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // 强制重置数据库连接
    try {
      debugPrint('正在重置数据库连接...');
      await widget.taskProvider.resetDatabaseConnection();
      debugPrint('数据库连接已重置');
    } catch (e) {
      debugPrint('重置数据库连接失败: $e');
    }

    // 执行实际的数据加载
    try {
      debugPrint('===== _loadData 开始 =====');
      await widget.taskProvider.loadData();
      debugPrint('===== taskProvider.loadData 完成 =====');
      debugPrint('任务数: ${widget.taskProvider.tasks.length}');
      debugPrint('isLoading: ${widget.taskProvider.isLoading}');

      // 数据加载完成后初始化提醒服务
      widget.reminderService.init(widget.taskProvider, navigatorKey);

      // 初始化剪贴板监视服务，默认开启
      clipboardMonitorService.init(navigatorKey, (content) {
        _showQuickAddWithContent(content);
      });
      // 默认启用剪贴板监视
      clipboardMonitorService.setEnabled(true);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('===== setState 完成，_isLoading = false =====');
      }
    } catch (e) {
      debugPrint('加载数据失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _reloadData() async {
    // 避免重复加载
    if (_isLoading) {
      debugPrint('正在加载数据中，跳过重复加载');
      return;
    }

    debugPrint('开始重新加载数据');
    setState(() {
      _isLoading = true;
      _error = null;
    });
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      debugPrint('===== _loadData 开始 =====');
      await widget.taskProvider.loadData();
      debugPrint('===== taskProvider.loadData 完成 =====');
      debugPrint('任务数: ${widget.taskProvider.tasks.length}');
      debugPrint('isLoading: ${widget.taskProvider.isLoading}');

      // 数据加载完成后初始化提醒服务
      widget.reminderService.init(widget.taskProvider, navigatorKey);

      // 初始化剪贴板监视服务，默认开启
      clipboardMonitorService.init(navigatorKey, (content) {
        _showQuickAddWithContent(content);
      });
      // 默认启用剪贴板监视
      clipboardMonitorService.setEnabled(true);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('===== setState 完成，_isLoading = false =====');
      }
    } catch (e) {
      debugPrint('加载数据失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// 显示快速添加任务窗口，并预填充剪贴板内容
  void _showQuickAddWithContent(String content) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showQuickAddModal(context, initialContent: content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.taskProvider),
        ChangeNotifierProvider.value(value: widget.settingsProvider),
        ChangeNotifierProvider.value(value: appSettings),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: settings.isZh ? '智能任务助手' : 'Smart Task Assistant',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.themeMode,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              AppLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('en', 'US'),
            ],
            locale: settings.locale,
            home: _buildHome(),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 24),
                  Text(
                    '加载中...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: Colors.white70),
                    const SizedBox(height: 24),
                    const Text(
                      '加载失败',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _error = null;
                        });
                        _loadData();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}
