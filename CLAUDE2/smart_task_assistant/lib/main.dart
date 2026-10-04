import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, EventChannel;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/task_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/habit_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/add_task_screen.dart';
import 'services/reminder_service.dart';
import 'services/speech_input_service.dart';
import 'services/task_comment_service.dart';
import 'services/tts_service.dart';
import 'services/clipboard_monitor_service.dart';
import 'widgets/quick_add_modal.dart';
import 'widgets/reminder_action_dialog.dart';
import 'widgets/habit_reminder_dialog.dart';
import 'utils/app_localizations.dart';
import 'database/database_helper.dart';

// 全局导航键，用于提醒服务显示弹窗
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 全局设置状态
class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light; // 默认浅色主题
  Locale _locale = const Locale('zh', 'CN');
  bool _clipboardMonitorEnabled = false; // 默认关闭：剪贴板监控涉及隐私，需用户主动开启
  bool _notificationsEnabled = true;

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

  // 恢复"系统识别不可靠"持久化标志（华为识别服务卡死过则直接走离线引擎）
  SpeechInputService.instance.loadSystemAsrUnreliable();

  // 全局错误边界：任何 widget build 抛异常时显示友好提示，避免 release 模式渲染成白屏；
  // 同时打印异常堆栈，便于定位偶发性白页面的根因。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint(
        '===== Widget build error =====\n${details.exception}\n${details.stack}');
    // 把异常摘要展示在页面上（可选中复制/截图）。release 模式下 debugPrint 不可见，
    // 这样用户能把错误信息反馈出来，便于定位偶发性渲染异常的根因。
    final errorSummary = details.exception.toString();
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 44, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('页面渲染异常',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      errorSummary,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('请下拉刷新或重启应用',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  };

  initializeDateFormatting();

  // 异步异常全局兜底：release 模式下，任何 fire-and-forget Future 抛出的未捕获异常
  // 会被 Dart VM 转成原生崩溃（"应用停止运行"）。runZonedGuarded 把这类异常转为
  // 可记录的非致命错误，避免 App 崩溃。必须在 runApp 之前调用。
  runZonedGuarded(() {
    // Flutter 框架自身（widget build 等）的同步异常兜底
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint(
          '===== FlutterError =====\n${details.exception}\n${details.stack}');
    };

    // 创建 Provider 实例
    final taskProvider = TaskProvider();
    final settingsProvider = SettingsProvider();
    final habitProvider = HabitProvider();

    // 初始化提醒服务（使用单例实例）
    final reminderService = ReminderService();

    // 设置提醒状态重置回调
    taskProvider.onReminderReset = reminderService.clearReminderState;
    habitProvider.onReminderReset = reminderService.clearHabitReminderState;

    runApp(MyApp(
      taskProvider: taskProvider,
      settingsProvider: settingsProvider,
      habitProvider: habitProvider,
      reminderService: reminderService,
    ));
  }, (error, stack) {
    // zone 内所有未捕获的异步异常都到这里，记录但不崩溃
    debugPrint('===== 未捕获的异步异常 =====\n$error\n$stack');
  });
}

class MyApp extends StatefulWidget {
  final TaskProvider taskProvider;
  final SettingsProvider settingsProvider;
  final HabitProvider habitProvider;
  final ReminderService reminderService;

  const MyApp({
    super.key,
    required this.taskProvider,
    required this.settingsProvider,
    required this.habitProvider,
    required this.reminderService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _error;

  // Native reminder channels
  static const _reminderMethodChannel =
      MethodChannel('com.smarttask.smart_task_assistant/reminder');
  static const _reminderEventChannel =
      EventChannel('com.smarttask.smart_task_assistant/reminder_events');
  StreamSubscription? _reminderEventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Cancel native reminder event subscription
    _reminderEventSubscription?.cancel();

    // 不要停止原生提醒服务！关闭APP后需要继续运行
    // 只有用户在设置中手动停止才会调用 stopService

    // 释放服务资源，防止内存泄漏
    widget.reminderService.dispose();

    // 只在服务已初始化时才释放剪贴板监视服务
    if (clipboardMonitorService.isInitialized) {
      clipboardMonitorService.dispose();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('===== 应用生命周期状态改变: $state =====');

    switch (state) {
      case AppLifecycleState.resumed:
        // 应用从后台恢复
        _notifyNativeForeground();
        widget.reminderService.isAppForeground = true;
        // 回前台重载 snooze：通知栏「延后10分钟」由原生直写 prefs，
        // 不重载的话 Flutter 检查链无此记录，会立即再次弹窗
        widget.reminderService
            .reloadSnoozedFromPrefs()
            .catchError((e) => debugPrint('重载 snooze 失败（已忽略）: $e'));
        // 仅刷新内存数据（后台期间原生层可能修改过 DB）。
        // 不再强制重置数据库连接：database getter 自带 ping 失效检测，
        // 真正失效时会自动重连，无需每次回前台都关闭正常连接并重建。
        debugPrint('应用恢复，刷新内存数据...');
        _reloadData();
        break;
      case AppLifecycleState.paused:
        // 应用进入后台
        _notifyNativeBackground();
        widget.reminderService.isAppForeground = false;
        debugPrint('应用进入后台');
        break;
      case AppLifecycleState.detached:
        // 应用即将被终止 - 重置所有单例连接
        _notifyNativeBackground();
        widget.reminderService.isAppForeground = false;
        debugPrint('应用即将被终止，重置所有单例连接');
        _resetAllConnections();
        break;
      case AppLifecycleState.inactive:
        // 部分 Android 机型自然熄屏只会先进入 inactive/hidden，不一定立刻 paused。
        // 提前交给原生提醒服务接管，避免熄屏后 Flutter 层跳过检查而原生仍以为在前台。
        _notifyNativeBackground();
        widget.reminderService.isAppForeground = false;
        debugPrint('应用处于非活动状态，提醒交给原生服务接管');
        break;
      case AppLifecycleState.hidden:
        // 应用被隐藏
        _notifyNativeBackground();
        widget.reminderService.isAppForeground = false;
        debugPrint('应用被隐藏，提醒交给原生服务接管');
        break;
    }
  }

  // --- Native reminder service ---

  Future<void> _startNativeReminderService() async {
    if (!Platform.isAndroid) return;
    try {
      // 先通知前台，防止 startService 触发时 isAppForeground=false 导致误报
      await _reminderMethodChannel.invokeMethod('notifyAppForeground');
      await _reminderMethodChannel.invokeMethod('startService');
      debugPrint('Native reminder service started');

      // 取消之前的订阅，防止重复
      await _reminderEventSubscription?.cancel();

      // Listen for native reminder events
      _reminderEventSubscription =
          _reminderEventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is String) {
            final map = jsonDecode(event) as Map<String, dynamic>;
            _handleReminderEvent(map);
          }
        },
        onError: (error) {
          debugPrint('Reminder event stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to start native reminder service: $e');
    }
  }

  Future<void> _notifyNativeForeground() async {
    if (!Platform.isAndroid) return;
    try {
      await _reminderMethodChannel.invokeMethod('notifyAppForeground');
    } catch (e) {
      debugPrint('Failed to notify native foreground: $e');
    }
  }

  /// 注入提醒弹窗构建（依赖倒置：ReminderService 不直接依赖 widgets，
  /// 弹窗的 UI 构建留在 UI 层，用户选择的处理逻辑留在服务层）
  void _wireReminderDialogs() {
    final service = widget.reminderService;
    service.showTaskReminderDialog = (task, onAction, onClosed) {
      final context = navigatorKey.currentContext;
      if (context == null) {
        onClosed();
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ReminderActionDialog(
          task: task,
          onAction: onAction,
        ),
      ).then((_) => onClosed());
    };
    service.showHabitReminderDialog = (habit, onClosed) {
      final context = navigatorKey.currentContext;
      if (context == null) {
        onClosed();
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => HabitReminderDialog(habit: habit),
      ).then((_) => onClosed());
    };
  }

  Future<void> _notifyNativeBackground() async {
    if (!Platform.isAndroid) return;
    try {
      await _reminderMethodChannel.invokeMethod('notifyAppBackground');
    } catch (e) {
      debugPrint('Failed to notify native background: $e');
    }
  }

  Future<void> _clearNativeReminderState(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _reminderMethodChannel
          .invokeMethod('clearContinualState', {'id': id});
    } catch (e) {
      debugPrint('Failed to clear native reminder state: $e');
    }
  }

  void _handleReminderEvent(Map<String, dynamic> event) {
    final id = event['id'] as String? ?? '';
    final type = event['type'] as String? ?? 'task';
    final action = event['action'] as String? ?? '';

    debugPrint('Native reminder event: id=$id type=$type action=$action');

    switch (action) {
      case 'shown':
        // Mark as shown in Flutter layer to avoid duplicate dialog
        if (type == 'task') {
          widget.reminderService.markShown(id);
        }
        break;
      case 'snoozed':
        final minutes = event['snoozeMinutes'] as int? ?? 10;
        widget.reminderService.setSnooze(id, minutes);
        break;
      case 'dismissed':
        if (type == 'task') {
          // Update task's reminder_dismissed field via provider
          widget.taskProvider.dismissReminder(id).catchError((e) {
            debugPrint('dismissReminder 失败（已忽略）: $e');
          });
        }
        break;
      case 'completed':
        if (type == 'habit') {
          // Log habit completion via provider
          widget.habitProvider.logCompletion(id).then<void>(
            (_) {},
            onError: (Object e, StackTrace stackTrace) {
              debugPrint('logCompletion 失败（已忽略）: $e');
            },
          );
          // 清除原生层提醒状态，停止持续提醒
          _clearNativeReminderState(id);
        }
        break;
      case 'edit':
        if (type == 'task') {
          // 导航到任务编辑页
          final task =
              widget.taskProvider.tasks.where((t) => t.id == id).firstOrNull;
          if (task != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => AddTaskScreen(task: task),
              ),
            );
          }
        }
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

  /// 仅刷新内存数据，不重置数据库连接（用于回前台等高频场景）。
  ///
  /// database getter 内部已对 sqlite_master 做 ping 检测，连接真正失效时会
  /// 自动重连——所以无需每次回前台都关闭正常连接。
  Future<void> _reloadData() async {
    debugPrint('Reloading in-memory data (no db reset)');
    setState(() {
      _isLoading = true;
      _error = null;
    });
    await _loadData(resetDatabase: false);
  }

  Future<void> _loadData({bool resetDatabase = false}) async {
    try {
      if (resetDatabase) {
        try {
          await widget.taskProvider.resetDatabaseConnection();
        } catch (e) {
          debugPrint('Failed to reset database connection: $e');
        }
      }

      debugPrint('===== _loadData 开始 =====');

      // 先加载设置（包括 AI 配置）
      await widget.settingsProvider.loadSettings();
      widget.taskProvider.autoCompleteParentTasks =
          widget.settingsProvider.autoCompleteParentTask;
      debugPrint('===== settingsProvider.loadSettings 完成 =====');

      // 同步 AI 配置到 AIService
      await widget.settingsProvider.syncAIConfig();
      debugPrint('===== settingsProvider.syncAIConfig 完成 =====');

      await widget.taskProvider.loadData();
      debugPrint('===== taskProvider.loadData 完成 =====');
      debugPrint('任务数: ${widget.taskProvider.tasks.length}');
      debugPrint('isLoading: ${widget.taskProvider.isLoading}');

      // 加载习惯数据
      await widget.habitProvider.loadData();
      debugPrint('===== habitProvider.loadData 完成 =====');
      debugPrint('习惯数: ${widget.habitProvider.habits.length}');

      // 异步预热评论内存缓存，避免首次打开任务详情时阻塞读盘数秒
      // fire-and-forget：必须加 catchError，否则异常会触发原生崩溃
      TaskCommentService.instance.getAllComments().then<void>(
        (_) {},
        onError: (Object e, StackTrace stackTrace) {
          debugPrint('预热评论缓存失败（已忽略）: $e');
        },
      );

      // 预初始化 TTS 引擎（避免首次播报时延迟）
      await TTSService().init();
      TTSService().volume = widget.settingsProvider.ttsVolume;
      debugPrint('===== TTSService 预初始化完成 =====');

      // 数据加载完成后初始化提醒服务（fire-and-forget，加 catchError 防崩溃）
      widget.reminderService
          .init(
        widget.taskProvider,
        widget.habitProvider,
        widget.settingsProvider,
        navigatorKey,
      )
          .catchError((e) {
        debugPrint('提醒服务初始化失败（已忽略）: $e');
      });

      // 注入提醒弹窗构建（依赖倒置：服务层不直接依赖 widgets）
      _wireReminderDialogs();

      // 启动原生提醒服务（Android）
      await _startNativeReminderService();

      // 初始化剪贴板监视服务，默认开启
      clipboardMonitorService.init(navigatorKey, (content) {
        _showQuickAddWithContent(content);
      });
      // 按用户设置启用剪贴板监控（默认关闭，涉及隐私需用户主动开启）
      clipboardMonitorService.setEnabled(appSettings.clipboardMonitorEnabled);

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
        ChangeNotifierProvider.value(value: widget.habitProvider),
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
      return _buildLoadingPage();
    }

    if (_error != null) {
      return _buildErrorPage();
    }

    return const HomeScreen();
  }

  Widget _buildLoadingPage() {
    return Scaffold(
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
    );
  }

  Widget _buildErrorPage() {
    return Scaffold(
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
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.white70,
                ),
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
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
    );
  }
}
