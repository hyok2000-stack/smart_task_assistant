import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';

import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../providers/habit_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/tag_management_dialog.dart';
import '../services/ai_service.dart';
import '../services/backend_api_service.dart';
import '../services/tts_service.dart';
import '../services/export_service.dart';
import '../database/storage_service.dart';
import 'sync_center_screen.dart';

// 条件导入：文件操作（Web和移动端）
import '../utils/platform_file_stub.dart'
    if (dart.library.html) '../utils/platform_file_web.dart'
    if (dart.library.io) '../utils/platform_file_native.dart';

/// 设置页面 - 传统列表布局
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _isTestingConnection = false;
  String? _testConnectionResult;
  bool _testConnectionSuccess = false;
  final TextEditingController _localLLMAddressController =
      TextEditingController();
  final TextEditingController _localLLMModelController =
      TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiBaseController = TextEditingController();
  final TextEditingController _apiModelController = TextEditingController();
  final TextEditingController _backendBaseUrlController =
      TextEditingController();
  final TextEditingController _backendAccountController =
      TextEditingController();
  final TextEditingController _backendPasswordController =
      TextEditingController();
  final TextEditingController _registerNicknameController =
      TextEditingController();
  final TextEditingController _registerPhoneController =
      TextEditingController();
  final TextEditingController _registerPasswordController =
      TextEditingController();
  final TextEditingController _registerEmailController =
      TextEditingController();
  final TextEditingController _registerInviteCodeController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsToControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshReminderPermissionState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localLLMAddressController.dispose();
    _localLLMModelController.dispose();
    _apiKeyController.dispose();
    _apiBaseController.dispose();
    _apiModelController.dispose();
    _backendBaseUrlController.dispose();
    _backendAccountController.dispose();
    _backendPasswordController.dispose();
    _registerNicknameController.dispose();
    _registerPhoneController.dispose();
    _registerPasswordController.dispose();
    _registerEmailController.dispose();
    _registerInviteCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 正常返回时清除导航恢复标记，避免下次启动误跳转
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('_restore_tab_index');
      });
      _refreshReminderPermissionState();
    }
  }

  Future<void> _refreshReminderPermissionState() async {
    if (!Platform.isAndroid) return;
    await Future.wait([
      _checkReminderServiceRunning(),
      _checkFullScreenPermission(),
      _checkNotificationPermission(),
      _checkExactAlarmPermission(),
      _checkBatteryOptimization(),
    ]);
    if (mounted) setState(() {});
  }

  void _loadSettingsToControllers() {
    final settings = context.read<SettingsProvider>();
    _localLLMAddressController.text = settings.localLLMAddress;
    _localLLMModelController.text = settings.localLLMModel;
    _apiKeyController.text = settings.apiKey;
    _apiBaseController.text = settings.apiBase;
    _apiModelController.text = settings.apiModel;
    BackendApiService.instance.init().then((_) {
      if (!mounted) return;
      final backend = BackendApiService.instance;
      _backendBaseUrlController.text = backend.baseUrl;
      _backendAccountController.text =
          backend.account ?? _backendAccountController.text;
      _backendPasswordController.text =
          backend.password ?? _backendPasswordController.text;
      setState(() {});
    }).catchError((e) {
      debugPrint('BackendApiService 初始化失败（已忽略）: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(l.navSettings),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.textPrimaryColor,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimaryColor,
        ),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('通知'),
          _buildNotificationSettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('AI服务'),
          _buildAISettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('标签管理'),
          _buildTagManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('数据'),
          _buildDataManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('云同步'),
          _buildBackendSyncSettings(context),
          const SizedBox(height: 32),
          _buildSectionHeader('设置管理'),
          _buildSettingsManagement(context),
          const SizedBox(height: 32),
          _buildSectionHeader('关于'),
          _buildAboutSection(context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('选择语言'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption(context, settings, 'zh', '简体中文'),
            const SizedBox(height: 8),
            _buildLanguageOption(context, settings, 'en', 'English'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context,
    SettingsProvider settings,
    String languageCode,
    String languageName,
  ) {
    final isSelected = settings.locale.languageCode == languageCode;
    return InkWell(
      onTap: () {
        settings.setLocale(
          Locale(languageCode, languageCode == 'zh' ? 'CN' : 'US'),
        );
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primaryColor : Colors.grey,
            ),
            const SizedBox(width: 12),
            Text(
              languageName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppTheme.primaryColor
                    : AppTheme.textPrimaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettings(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildListTile(
                icon: Icons.content_copy_outlined,
                title: '剪贴板监视',
                subtitle: '粘贴内容时自动弹出任务创建窗口',
                trailing: Switch(
                  value: settings.clipboardMonitor,
                  onChanged: (value) {
                    settings.setClipboardMonitor(value);
                  },
                  activeThumbColor: AppTheme.primaryColor,
                ),
              ),
              _buildDivider(),
              _buildListTile(
                icon: Icons.account_tree_outlined,
                title: '子任务全部完成时完成父任务',
                subtitle: '关闭后，父任务需要手动完成',
                trailing: Switch(
                  value: settings.autoCompleteParentTask,
                  onChanged: (value) {
                    settings.setAutoCompleteParentTask(value);
                    context.read<TaskProvider>().autoCompleteParentTasks =
                        value;
                  },
                  activeThumbColor: AppTheme.primaryColor,
                ),
              ),
              if (Platform.isAndroid) ...[
                _buildDivider(),
                _buildReminderServiceSettings(context),
              ],
              _buildDivider(),
              // 语音音量滑块
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up_outlined,
                        color: AppTheme.textSecondaryColor),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '语音音量',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimaryColor,
                            ),
                          ),
                          Slider(
                            value: settings.ttsVolume,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            activeColor: AppTheme.primaryColor,
                            label: '${(settings.ttsVolume * 100).round()}%',
                            onChanged: (value) {
                              settings.setTtsVolume(value);
                              TTSService().volume = value;
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(settings.ttsVolume * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondaryColor,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReminderServiceSettings(BuildContext context) {
    return Column(
      children: [
        _buildListTile(
          icon: Icons.alarm_outlined,
          title: '后台提醒服务',
          subtitle: _isReminderServiceRunning ? '正在运行' : '关闭后应用不在后台时无法收到提醒',
          trailing: Switch(
            value: _isReminderServiceRunning,
            onChanged: (value) async {
              try {
                const channel = MethodChannel(
                    'com.smarttask.smart_task_assistant/reminder');
                if (value) {
                  await channel.invokeMethod('startService');
                } else {
                  await channel.invokeMethod('stopService');
                }
              } catch (_) {}
              await _checkReminderServiceRunning();
              if (mounted) setState(() {});
            },
            activeThumbColor: AppTheme.primaryColor,
          ),
        ),
        _buildDivider(),
        _buildListTile(
          icon: Icons.screen_lock_portrait_outlined,
          title: '锁屏弹出权限',
          subtitle:
              _hasFullScreenPermission ? '已允许，锁屏时可以显示全屏提醒' : '未允许，点击前往系统设置开启',
          trailing: _buildPermissionStatusTrailing(_hasFullScreenPermission),
          onTap: () => _requestFullScreenPermission(),
        ),
        _buildDivider(),
        _buildNotificationPermissionTile(),
        _buildDivider(),
        _buildExactAlarmPermissionTile(),
        _buildDivider(),
        _buildBatteryOptimizationTile(),
        _buildDivider(),
        Consumer<SettingsProvider>(
          builder: (context, settings, _) => Column(
            children: [
              _buildListTile(
                icon: Icons.bedtime_outlined,
                title: '免打扰时间',
                subtitle: settings.quietHoursEnabled
                    ? '${settings.quietHoursStart.toString().padLeft(2, '0')}:00 - ${settings.quietHoursEnd.toString().padLeft(2, '0')}:00'
                    : '关闭',
                trailing: Switch(
                  value: settings.quietHoursEnabled,
                  onChanged: settings.setQuietHoursEnabled,
                  activeThumbColor: AppTheme.primaryColor,
                ),
                onTap: () => _selectQuietHours(settings),
              ),
              _buildDivider(),
              _buildListTile(
                icon: Icons.task_alt_outlined,
                title: '任务提醒',
                subtitle: '声音与震动分别控制',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '声音',
                      onPressed: () => settings.setTaskReminderSoundEnabled(
                          !settings.taskReminderSoundEnabled),
                      icon: Icon(settings.taskReminderSoundEnabled
                          ? Icons.volume_up
                          : Icons.volume_off),
                    ),
                    IconButton(
                      tooltip: '震动',
                      onPressed: () => settings.setTaskReminderVibrationEnabled(
                          !settings.taskReminderVibrationEnabled),
                      icon: Icon(settings.taskReminderVibrationEnabled
                          ? Icons.vibration
                          : Icons.phone_android),
                    ),
                  ],
                ),
              ),
              _buildDivider(),
              _buildListTile(
                icon: Icons.self_improvement_outlined,
                title: '习惯提醒',
                subtitle: '声音与震动分别控制',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '声音',
                      onPressed: () => settings.setHabitReminderSoundEnabled(
                          !settings.habitReminderSoundEnabled),
                      icon: Icon(settings.habitReminderSoundEnabled
                          ? Icons.volume_up
                          : Icons.volume_off),
                    ),
                    IconButton(
                      tooltip: '震动',
                      onPressed: () =>
                          settings.setHabitReminderVibrationEnabled(
                              !settings.habitReminderVibrationEnabled),
                      icon: Icon(settings.habitReminderVibrationEnabled
                          ? Icons.vibration
                          : Icons.phone_android),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildDivider(),
        _buildListTile(
          icon: Icons.play_circle_outline_rounded,
          title: '提醒自测',
          subtitle: '立即播放一次测试提醒，确认声音正常',
          onTap: () async {
            await TTSService().speak(text: '这是提醒测试，任务提醒功能正常');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('测试提醒已播放')),
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _selectQuietHours(SettingsProvider settings) async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.quietHoursStart, minute: 0),
      helpText: '选择免打扰开始时间',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.quietHoursEnd, minute: 0),
      helpText: '选择免打扰结束时间',
    );
    if (end == null) return;
    settings.setQuietHours(startHour: start.hour, endHour: end.hour);
    settings.setQuietHoursEnabled(true);
  }

  bool _isReminderServiceRunning = false;
  bool _isBatteryOptimized = true;
  bool _notificationsEnabled = true;
  bool _canScheduleExactAlarms = true;

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      _isBatteryOptimized =
          await channel.invokeMethod('isBatteryOptimized') ?? true;
    } catch (_) {
      _isBatteryOptimized = true;
    }
  }

  Widget _buildBatteryOptimizationTile() {
    return _buildListTile(
      icon: Icons.battery_alert_outlined,
      title: '电池优化',
      subtitle: _isBatteryOptimized ? '未豁免，点击申请忽略电池优化' : '已豁免，后台服务可正常运行',
      trailing: _buildPermissionStatusTrailing(!_isBatteryOptimized),
      onTap: () async {
        if (!_isBatteryOptimized) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已豁免电池优化，后台服务可正常运行'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        try {
          // 保存导航状态，防止进程被杀后丢失设置页面
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('_restore_tab_index', 5);

          const channel =
              MethodChannel('com.smarttask.smart_task_assistant/reminder');
          await channel.invokeMethod('requestIgnoreBatteryOptimization');
        } catch (_) {}
        // didChangeAppLifecycleState will refresh when user returns
      },
    );
  }

  Widget _buildNotificationPermissionTile() {
    return _buildListTile(
      icon: Icons.notifications_active_outlined,
      title: '通知权限',
      subtitle:
          _notificationsEnabled ? '已允许，任务提醒可以正常显示通知' : '未允许，锁屏或休眠时可能收不到提醒',
      trailing: _buildPermissionStatusTrailing(_notificationsEnabled),
      onTap: () async {
        await _openNotificationSettings();
        // 权限状态由 didChangeAppLifecycleState(resumed) 在返回时刷新
        // 避免与生命周期回调并发导致 Flutter engine 异常
      },
    );
  }

  Widget _buildExactAlarmPermissionTile() {
    return _buildListTile(
      icon: Icons.alarm_on_outlined,
      title: '精确闹钟权限',
      subtitle:
          _canScheduleExactAlarms ? '已允许，休眠时可按计划唤醒检查提醒' : '未允许，手机休眠后提醒可能明显延迟',
      trailing: _buildPermissionStatusTrailing(_canScheduleExactAlarms),
      onTap: () async {
        await _openExactAlarmSettings();
        // 权限状态由 didChangeAppLifecycleState(resumed) 在返回时刷新
        // 避免与生命周期回调并发导致 Flutter engine 异常
      },
    );
  }

  Widget _buildPermissionStatusTrailing(bool allowed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          allowed ? Icons.check_circle_outline : Icons.error_outline,
          color: allowed ? Colors.green : Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
      ],
    );
  }

  bool _hasFullScreenPermission = false;

  Future<void> _checkReminderServiceRunning() async {
    if (!Platform.isAndroid) return;
    try {
      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      _isReminderServiceRunning =
          await channel.invokeMethod('isServiceRunning') ?? false;
    } catch (_) {
      _isReminderServiceRunning = false;
    }
  }

  Future<void> _checkFullScreenPermission() async {
    if (!Platform.isAndroid) return;
    try {
      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      _hasFullScreenPermission =
          await channel.invokeMethod('hasFullScreenPermission') ?? true;
    } catch (_) {
      _hasFullScreenPermission = true;
    }
  }

  Future<void> _requestFullScreenPermission() async {
    if (!Platform.isAndroid) return;
    try {
      // 保存导航状态，防止进程被杀后丢失设置页面
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('_restore_tab_index', 5);

      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      final granted = await channel.invokeMethod('requestFullScreenPermission');
      _hasFullScreenPermission = granted == true;
      if (mounted) {
        if (_hasFullScreenPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('锁屏弹出权限已开启'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在系统设置中开启全屏通知权限'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _checkNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      _notificationsEnabled =
          await channel.invokeMethod('areNotificationsEnabled') ?? true;
    } catch (_) {
      _notificationsEnabled = true;
    }
  }

  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      // 保存导航状态，防止进程被杀后丢失设置页面
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('_restore_tab_index', 5);

      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      await channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<void> _checkExactAlarmPermission() async {
    if (!Platform.isAndroid) return;
    try {
      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      _canScheduleExactAlarms =
          await channel.invokeMethod('canScheduleExactAlarms') ?? true;
    } catch (_) {
      _canScheduleExactAlarms = true;
    }
  }

  Future<void> _openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    try {
      // 保存导航状态，防止进程被杀后丢失设置页面
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('_restore_tab_index', 5);

      const channel =
          MethodChannel('com.smarttask.smart_task_assistant/reminder');
      await channel.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }

  Widget _buildAISettings(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              _buildListTile(
                icon: Icons.psychology_outlined,
                title: 'AI服务配置',
                subtitle: '配置本地大模型或远程API',
                trailing:
                    const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
                onTap: () {
                  _showAISettingsDialog(context, settings);
                },
              ),
              _buildDivider(),
              // 显示当前使用的 AI 模型
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 68, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前使用: ${settings.getCurrentAIModelName()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagManagement(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildDefaultTagsSection(),
          _buildDivider(),
          _buildListTile(
            icon: Icons.add_circle_outline,
            title: '添加标签',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              showTagManagementDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultTagsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.label_outline,
                color: AppTheme.textSecondaryColor,
                size: 20,
              ),
              SizedBox(width: 12),
              Text(
                '默认标签',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTagChip('工作', '#10B981'),
              _buildTagChip('个人', '#3B82F6'),
              _buildTagChip('紧急', '#EF4444'),
              _buildTagChip('学习', '#8B5CF6'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String label, String colorCode) {
    final color = Color(int.parse(colorCode.replaceFirst('#', '0xFF')));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDataManagement(BuildContext context) {
    final l = context.l;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.file_download_outlined,
            title: l.exportData,
            subtitle: '导出所有任务数据',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _exportData(context, l),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.table_chart_outlined,
            title: '导出 CSV',
            subtitle: '以 CSV 格式分享任务列表',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () async {
              final taskProvider = context.read<TaskProvider>();
              await ExportService.instance.exportAndShare(taskProvider.tasks);
            },
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.file_upload_outlined,
            title: l.importData,
            subtitle: '导入任务数据',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _importData(context, l),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.delete_outline,
            title: l.clearData,
            subtitle: '清除所有数据',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _clearData(context, l),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsManagement(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.restore_outlined,
            title: '重置所有设置',
            subtitle: '恢复到默认配置',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _showResetSettingsDialog(context, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendSyncSettings(BuildContext context) {
    final backend = BackendApiService.instance;
    final taskProvider = context.watch<TaskProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildBackendSyncStatusPanel(context, backend, taskProvider),
          _buildDivider(),
          _buildListTile(
            icon: Icons.cloud_outlined,
            title: backend.isLoggedIn ? '已登录：${backend.nickname}' : '登录后台同步',
            subtitle:
                backend.isLoggedIn ? '地址：${backend.baseUrl}' : '配置后台地址、账号和密码',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _showBackendLoginDialog(context),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.sync_outlined,
            title: taskProvider.isBackendSyncing ? '正在同步任务' : '立即同步任务',
            subtitle: _backendSyncSubtitle(taskProvider),
            trailing: taskProvider.isBackendSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: taskProvider.isBackendSyncing
                ? null
                : () => _syncBackendTasks(context),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.sync_problem_outlined,
            title: '同步中心',
            subtitle: '查看同步状态、失败记录和重试队列',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SyncCenterScreen()),
            ),
          ),
          _buildDivider(),
          _buildListTile(
            icon: Icons.group_outlined,
            title: '团队管理',
            subtitle: '创建或查看团队',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () => _showTeamDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBackendSyncStatusPanel(
    BuildContext context,
    BackendApiService backend,
    TaskProvider taskProvider,
  ) {
    final loggedIn = taskProvider.isBackendLoggedIn;
    final error = taskProvider.backendSyncError;
    final pendingCount = taskProvider.pendingBackendSyncCount;

    Color color;
    IconData icon;
    String title;
    if (!loggedIn) {
      color = AppTheme.textHintColor;
      icon = Icons.cloud_off_outlined;
      title = '云同步未登录';
    } else if (taskProvider.isBackendSyncing) {
      color = AppTheme.infoColor;
      icon = Icons.sync_rounded;
      title = '正在同步';
    } else if (error != null && error.isNotEmpty) {
      color = AppTheme.errorColor;
      icon = Icons.error_outline;
      title = '同步需要处理';
    } else {
      color = AppTheme.successColor;
      icon = Icons.cloud_done_outlined;
      title = '云同步正常';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSyncInfoRow(
                '登录状态', loggedIn ? '已登录：${backend.nickname ?? '-'}' : '未登录'),
            _buildSyncInfoRow('后台地址', backend.baseUrl),
            _buildSyncInfoRow(
              '最后同步',
              taskProvider.lastBackendSyncAt == null
                  ? '尚未完成同步'
                  : _formatDateTime(taskProvider.lastBackendSyncAt!),
            ),
            _buildSyncInfoRow('待重试变更', '$pendingCount 个'),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '最近错误：$error',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.errorColor,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textHintColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondaryColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _backendSyncSubtitle(TaskProvider taskProvider) {
    if (!taskProvider.isBackendLoggedIn) {
      return '请先登录后台同步';
    }
    if (taskProvider.isBackendSyncing) {
      return '正在与后台交换任务和评论';
    }
    final error = taskProvider.backendSyncError;
    if (error != null && error.isNotEmpty) {
      final pending = taskProvider.pendingBackendSyncCount;
      return pending > 0 ? '有 $pending 个变更待重试' : '上次同步失败，点此重试';
    }
    return taskProvider.lastBackendSyncAt == null
        ? '从后台拉取新增任务，保持本地优先'
        : '最后同步 ${_formatDateTime(taskProvider.lastBackendSyncAt!)}';
  }

  Widget _buildAboutSection(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '版本 ${settings.appVersion}',
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textHintColor),
            onTap: () {
              _showAboutDialog(context, settings);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool showTrailing = true,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondaryColor),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimaryColor,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppTheme.textHintColor),
            )
          : null,
      trailing: trailing ??
          (showTrailing
              ? const Icon(Icons.chevron_right, color: AppTheme.textHintColor)
              : null),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 0.5, indent: 68, endIndent: 0);
  }

  void _showBackendLoginDialog(BuildContext context) {
    final backend = BackendApiService.instance;
    if (_backendBaseUrlController.text.isEmpty) {
      _backendBaseUrlController.text = backend.baseUrl;
    }
    var isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('后台同步登录'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 420
                  ? 420
                  : MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _backendBaseUrlController,
                    decoration: const InputDecoration(
                      labelText: '后台地址',
                      hintText: 'http://localhost:4100/api',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backendAccountController,
                    decoration: const InputDecoration(labelText: '账号'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _backendPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              Navigator.pop(context);
                              _showRegisterDialog(context);
                            },
                      child: const Text('没有账号？注册新账号'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (backend.isLoggedIn)
                TextButton(
                  onPressed: isLoading
                      ? null
                    : () async {
                        final taskProvider = context.read<TaskProvider>();
                        // 登出前询问是否清除本地任务数据（防止下一个账号串库）
                        final clearLocal =
                            await _confirmLogoutClearData(context);
                        await backend.logout();
                        if (clearLocal) {
                          // 清除前先备份，给用户留后悔药
                          await taskProvider.clearAllData();
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(clearLocal
                                ? '已退出登录并清除本地数据'
                                : '已退出后台登录（本地数据已保留）'),
                          ),
                        );
                      },
                  child: const Text('退出登录'),
                ),
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setDialogState(() => isLoading = true);
                        final taskProvider = context.read<TaskProvider>();
                        try {
                          final session = await backend.login(
                            account: _backendAccountController.text.trim(),
                            password: _backendPasswordController.text,
                            baseUrl: _backendBaseUrlController.text.trim(),
                            rememberPassword: true,
                          );
                          await backend.bindDevice(
                            deviceName:
                                kIsWeb ? 'Web APP' : Platform.localHostname,
                            platform: kIsWeb ? 'web' : Platform.operatingSystem,
                          );
                          final syncedCount =
                              await taskProvider.syncAllWithBackend();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '已登录：${session.nickname}，同步 $syncedCount 个云端变更',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('登录失败：$e')),
                          );
                        } finally {
                          if (mounted) {
                            setDialogState(() => isLoading = false);
                          }
                        }
                      },
                child: Text(isLoading ? '登录中...' : '登录'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 登出时确认是否清除本地任务数据（防跨账号数据串库）。
  /// 返回 true 表示用户选择清除本地数据。
  Future<bool> _confirmLogoutClearData(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('退出登录'),
        content: const Text(
          '是否同时清除本地的任务和标签数据？\n\n'
          '• 清除：避免下一个账号登录时数据混淆（推荐在共享设备上）\n'
          '• 保留：本地离线任务不受影响（清除前会自动备份）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('保留数据'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除并退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showRegisterDialog(BuildContext context) {
    final backend = BackendApiService.instance;
    if (_backendBaseUrlController.text.isEmpty) {
      _backendBaseUrlController.text = backend.baseUrl;
    }
    var isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('注册账号'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 420
                  ? 420
                  : MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _backendBaseUrlController,
                      decoration: const InputDecoration(
                        labelText: '后台地址',
                        hintText: 'http://localhost:4100/api',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registerNicknameController,
                      decoration: const InputDecoration(
                        labelText: '昵称 *',
                        hintText: '输入昵称',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registerPhoneController,
                      decoration: const InputDecoration(
                        labelText: '手机号（可选）',
                        hintText: '13800000000',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registerEmailController,
                      decoration: const InputDecoration(
                        labelText: '邮箱（可选）',
                        hintText: 'user@example.com',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registerPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码 *',
                        hintText: '至少6位',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _registerInviteCodeController,
                      decoration: const InputDecoration(
                        labelText: '邀请码 *',
                        hintText: 'TEAM-XXXXXX',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.pop(context);
                        _showBackendLoginDialog(context);
                      },
                child: const Text('返回登录'),
              ),
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final nickname =
                            _registerNicknameController.text.trim();
                        final password = _registerPasswordController.text;
                        final inviteCode =
                            _registerInviteCodeController.text.trim();

                        if (nickname.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入昵称')),
                          );
                          return;
                        }
                        if (password.length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('密码至少6位')),
                          );
                          return;
                        }
                        if (inviteCode.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入邀请码')),
                          );
                          return;
                        }
                        final regPhone = _registerPhoneController.text.trim();
                        final regEmail = _registerEmailController.text.trim();
                        if (regPhone.isEmpty && regEmail.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('手机号和邮箱至少填写一项')),
                          );
                          return;
                        }

                        setDialogState(() => isLoading = true);
                        final taskProvider = context.read<TaskProvider>();
                        try {
                          final session = await backend.register(
                            nickname: nickname,
                            password: password,
                            inviteCode: inviteCode,
                            phone:
                                _registerPhoneController.text.trim().isNotEmpty
                                    ? _registerPhoneController.text.trim()
                                    : null,
                            email:
                                _registerEmailController.text.trim().isNotEmpty
                                    ? _registerEmailController.text.trim()
                                    : null,
                            baseUrl: _backendBaseUrlController.text.trim(),
                          );
                          await backend.bindDevice(
                            deviceName:
                                kIsWeb ? 'Web APP' : Platform.localHostname,
                            platform: kIsWeb ? 'web' : Platform.operatingSystem,
                          );
                          final syncedCount =
                              await taskProvider.syncAllWithBackend();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '注册成功：${session.nickname}，同步 $syncedCount 个云端变更',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('注册失败：$e')),
                          );
                        } finally {
                          if (mounted) {
                            setDialogState(() => isLoading = false);
                          }
                        }
                      },
                child: Text(isLoading ? '注册中...' : '注册'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTeamDialog(BuildContext context) {
    final backend = BackendApiService.instance;
    if (!backend.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后台同步')),
      );
      return;
    }
    final nameController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('团队管理',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  // 已加入的团队
                  StatefulBuilder(
                    builder: (context, setInner) {
                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: backend.getMyTeams(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return ErrorStateWidget(
                              compact: true,
                              onRetry: () => setInner(() {}),
                            );
                          }
                          final teams = snapshot.data ?? [];
                          if (teams.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('暂未加入任何团队',
                                  style: TextStyle(color: Colors.grey)),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('已加入的团队',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey)),
                              const SizedBox(height: 8),
                              ...teams.map((team) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.group,
                                        color: AppTheme.primaryColor),
                                    title: Text(team['name'] as String,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    subtitle: Text(
                                        'ID: ${(team['id'] as String).substring(0, 8)}...'),
                                  )),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const Divider(height: 24),
                  // 创建新团队
                  const Text('创建新团队',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            hintText: '输入团队名称',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          try {
                            await backend.createTeam(name: name);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('团队「$name」创建成功')),
                              );
                              Navigator.pop(context);
                              setState(() {});
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('创建失败：$e')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncBackendTasks(BuildContext context) async {
    try {
      final taskProvider = context.read<TaskProvider>();
      final count = await taskProvider.syncFromBackend();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步完成，新增 $count 个任务')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步失败：$e')),
      );
    }
  }

  void _showAISettingsDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('AI服务配置'),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 400
                  ? 400
                  : MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '选择服务模式',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.local,
                      '本地规则',
                      '使用本地规则引擎，无需网络连接',
                      setState,
                    ),
                    const SizedBox(height: 8),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.localLLM,
                      '本地大模型',
                      '连接本地部署的LLM（如Ollama）',
                      setState,
                    ),
                    const SizedBox(height: 8),
                    _buildCompactAIModeOption(
                      settings,
                      AIMode.remoteAPI,
                      '远程API',
                      '使用云端API服务（如OpenAI）',
                      setState,
                    ),
                    const SizedBox(height: 24),
                    if (settings.aiMode == AIMode.localLLM) ...[
                      _buildConfigSection('本地大模型配置', Icons.cloud_outlined, [
                        TextField(
                          decoration: InputDecoration(
                            labelText: '服务地址',
                            hintText: 'http://localhost:11434',
                            border: const OutlineInputBorder(),
                            errorText:
                                settings.isValidUrl(settings.localLLMAddress) ||
                                        settings.localLLMAddress.isEmpty
                                    ? null
                                    : '请输入有效的URL地址',
                          ),
                          controller: _localLLMAddressController,
                          onChanged: (value) {
                            settings.setLocalLLMAddress(value);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: InputDecoration(
                            labelText: '模型名称',
                            hintText: 'qwen2.5:7b',
                            border: const OutlineInputBorder(),
                            errorText: !settings.isValidModelName(
                              settings.localLLMModel,
                            )
                                ? '请输入模型名称'
                                : null,
                          ),
                          controller: _localLLMModelController,
                          onChanged: (value) {
                            settings.setLocalLLMModel(value);
                          },
                        ),
                      ]),
                    ],
                    if (settings.aiMode == AIMode.remoteAPI) ...[
                      _buildConfigSection(
                        '远程API配置',
                        Icons.cloud_queue_outlined,
                        [
                          _buildAPIKeyField(settings),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'API地址',
                              hintText: 'https://api.openai.com/v1',
                              border: const OutlineInputBorder(),
                              errorText:
                                  !settings.isValidUrl(settings.apiBase) &&
                                          settings.apiBase.isNotEmpty
                                      ? '请输入有效的URL地址'
                                      : null,
                            ),
                            controller: _apiBaseController,
                            onChanged: (value) {
                              settings.setAPIBase(value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: '模型名称',
                              hintText: 'gpt-3.5-turbo',
                              border: const OutlineInputBorder(),
                              errorText:
                                  !settings.isValidModelName(settings.apiModel)
                                      ? '请输入模型名称'
                                      : null,
                            ),
                            controller: _apiModelController,
                            onChanged: (value) {
                              settings.setAPIModel(value);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              Column(
                children: [
                  if (settings.aiMode != AIMode.local) ...[
                    TextButton.icon(
                      onPressed: _isTestingConnection
                          ? null
                          : () => _testConnection(
                              settings, settings.aiMode, setState),
                      icon: _isTestingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi, size: 18),
                      label: Text(_isTestingConnection ? '测试中...' : '测试连接'),
                    ),
                    // 显示测试结果
                    if (_testConnectionResult != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _testConnectionSuccess
                                ? AppTheme.successColor.withValues(alpha: 0.1)
                                : AppTheme.errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _testConnectionSuccess
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _testConnectionSuccess
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: _testConnectionSuccess
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testConnectionResult!,
                                  style: TextStyle(
                                    color: _testConnectionSuccess
                                        ? AppTheme.successColor
                                        : AppTheme.errorColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          // 同步 AI 配置到 AIService
                          await settings.syncAIConfig();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _showConfigSavedMessage(context, settings.aiMode);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCompactAIModeOption(
    SettingsProvider settings,
    AIMode mode,
    String title,
    String subtitle,
    StateSetter setState,
  ) {
    final isSelected = settings.aiMode == mode;
    return InkWell(
      onTap: () {
        settings.setAIMode(mode);
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primaryColor : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAPIKeyField(SettingsProvider settings) {
    bool obscureText = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return TextField(
          decoration: InputDecoration(
            labelText: 'API Key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: obscureText ? '显示' : '隐藏',
              icon: Icon(
                obscureText ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  obscureText = !obscureText;
                });
              },
            ),
          ),
          controller: _apiKeyController,
          onChanged: (value) {
            settings.setAPIKey(value);
          },
          obscureText: obscureText,
        );
      },
    );
  }

  void _testConnection(
    SettingsProvider settings,
    AIMode mode,
    StateSetter? dialogSetState,
  ) async {
    final setState = dialogSetState ?? this.setState;
    setState(() {
      _isTestingConnection = true;
      _testConnectionResult = null;
      _testConnectionSuccess = false;
    });

    try {
      final aiService = AIService();
      bool isConnected;

      if (mode == AIMode.localLLM) {
        isConnected = await aiService.testLocalLLMConnection(
          settings.localLLMAddress,
          settings.localLLMModel,
        );
      } else if (mode == AIMode.remoteAPI) {
        isConnected = await aiService.testAPIConnection(
          settings.apiKey,
          settings.apiBase,
          settings.apiModel,
        );
      } else {
        isConnected = true;
      }

      if (mounted) {
        setState(() {
          _testConnectionResult = isConnected ? '连接成功！' : '连接失败，请检查配置';
          _testConnectionSuccess = isConnected;
        });

        // 测试成功后，同步配置到 AIService 并刷新显示
        if (isConnected) {
          await settings.syncAIConfig();
          // 强制刷新界面以更新当前使用的模型信息
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testConnectionResult = '连接测试失败: $e';
          _testConnectionSuccess = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingConnection = false);
      }
    }
  }

  void _exportData(BuildContext context, AppLocalizations l) async {
    try {
      // 获取存储服务
      final storageService = getStorageService();

      // 生成导出数据（含任务全字段 + 标签 + 习惯 + 习惯日志，确保迁移无损）
      String exportData;
      if (kIsWeb && storageService is WebStorageService) {
        exportData = storageService.getExportData();
      } else {
        // 移动端或其他平台，从数据库获取完整数据
        final taskProvider = context.read<TaskProvider>();
        final tasks = taskProvider.tasks;
        final tags = taskProvider.tags;
        final habitProvider = context.read<HabitProvider>();

        // 扁平化习惯日志
        final allLogsByDate = await habitProvider.getAllLogsByDate();
        final flatHabitLogs = <Map<String, dynamic>>[];
        for (final logs in allLogsByDate.values) {
          for (final log in logs) {
            flatHabitLogs.add(log.toJson());
          }
        }

        final data = {
          'format': 'smart_task_full_backup',
          'version': '2.0',
          'tasks': tasks.map((t) => t.toJson()).toList(),
          'tags': tags.map((t) => t.toJson()).toList(),
          'habits': habitProvider.habits.map((h) => h.toJson()).toList(),
          'habitLogs': flatHabitLogs,
          'exportTime': DateTime.now().toIso8601String(),
        };
        exportData = jsonEncode(data);
      }

      // 生成文件名：任务列表_YYYYMMDD_HHMMSS.json
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = '任务列表_$timestamp.json';

      // 生成文件大小
      final bytes = utf8.encode(exportData);
      final kbSize = (bytes.length / 1024).toStringAsFixed(2);

      if (kIsWeb) {
        // Web平台使用下载方式
        downloadFile(exportData, fileName, 'application/json');
      } else {
        // 移动端保存到程序目录
        await exportDataToAppDir(
          data: exportData,
          fileName: fileName,
        );
      }

      // 显示成功对话框
      if (!context.mounted) return;
      _showExportSuccessDialog(context, fileName, kbSize, exportData);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.exportFailed}: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _showExportSuccessDialog(
    BuildContext context,
    String fileName,
    String size,
    String exportData,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.successColor,
                      AppTheme.successColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.file_download_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '导出数据',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 64,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '导出成功！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '数据已导出为以下文件',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.successColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_rounded,
                                color: AppTheme.successColor,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'JSON格式',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _importData(BuildContext context, AppLocalizations l) async {
    // 在进入任何 await 之前先取好 provider，避免跨异步间隙使用 context
    final taskProvider = context.read<TaskProvider>();
    try {
      String? content;
      String? fileName;

      if (kIsWeb) {
        // Web平台使用文件选择器
        bool fileSelected = false;

        selectFile(
          accept: '.json',
          onFileSelected: (selectedContent, selectedFileName) async {
            content = selectedContent;
            fileName = selectedFileName;
            fileSelected = true;
          },
          onError: (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${l.importFailed}: $error'),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
          },
        );

        // 等待文件选择完成
        await Future.delayed(const Duration(milliseconds: 100));

        // 如果没有选择文件，直接返回
        if (!fileSelected) {
          return;
        }
      } else {
        // 移动端：用系统文件选择器从任意位置导入备份文件
        // 支持 JSON 和 CSV 两种格式
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json', 'csv'],
        );

        if (result == null || result.files.single.path == null) {
          // 用户取消选择
          return;
        }

        final filePath = result.files.single.path!;
        fileName = result.files.single.name;
        try {
          final file = File(filePath);
          content = await file.readAsString();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('读取文件失败: $e'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }
      }

      // 检查是否获取到内容
      if (content == null) {
        return;
      }

      try {
        Map<String, dynamic> data;

        // 根据扩展名或内容判断格式：CSV 还是 JSON
        if (fileName?.toLowerCase().endsWith('.csv') == true ||
            content!.trimLeft().startsWith('\ufeffID,') ||
            content!.trimLeft().startsWith('ID,')) {
          // CSV 格式：用 ExportService 解析
          data = ExportService.instance.parseCSV(content!);
        } else {
          // JSON 格式
          data = jsonDecode(content!) as Map<String, dynamic>;
          // 验证数据格式
          if (!data.containsKey('tasks') || !data.containsKey('tags')) {
            throw Exception('无效的数据格式');
          }
        }

        // 导入数据（taskProvider 已在方法开头取得）

        if (kIsWeb) {
          // Web平台使用存储服务
          final storageService = getStorageService();
          if (storageService is! WebStorageService) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.importFailed),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }

          final success = await (storageService)
              .restoreFromBackup(data);

          if (!success) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.importFailed),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }
        } else {
          // 移动端直接导入数据（importData内部已经调用了loadData）
          await taskProvider.importData(data);

          // 显示导入成功对话框
          if (context.mounted) {
            _showImportSuccessDialog(
              context,
              fileName!,
              data['tasks']?.length ?? 0,
              data['tags']?.length ?? 0,
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l.importFailed}: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l.importFailed}: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// 显示导入来源选择对话框
  Future<String?> _showImportSourceDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.file_upload_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '选择导入方式',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildImportSourceOption(
                      context,
                      'internal',
                      Icons.folder_rounded,
                      '从应用目录导入',
                      '选择应用内部保存的备份文件',
                    ),
                    const SizedBox(height: 12),
                    _buildImportSourceOption(
                      context,
                      'external',
                      Icons.sd_card_rounded,
                      '从外部导入',
                      '从手机存储或其他应用选择文件',
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建导入来源选项
  Widget _buildImportSourceOption(
    BuildContext context,
    String source,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(context, source),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textHintColor,
            ),
          ],
        ),
      ),
    );
  }
  /// 显示导入文件选择对话框
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '今天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天 ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }

  void _showImportSuccessDialog(
    BuildContext context,
    String fileName,
    int taskCount,
    int tagCount,
  ) {
    final l = context.l;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.successColor,
                      AppTheme.successColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      '导入成功！',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.restoreSuccessCount('$taskCount', '$tagCount'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.successColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.insert_drive_file_rounded,
                            color: AppTheme.successColor,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearData(BuildContext context, AppLocalizations l) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.errorColor,
                      AppTheme.errorColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      '确认清除所有数据',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '此操作将永久删除所有任务和标签，无法恢复！',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);

                          try {
                            final taskProvider =
                                context.read<TaskProvider>();
                            await taskProvider.clearAllData();

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('所有数据已清除'),
                                  backgroundColor: AppTheme.successColor,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('清除失败: $e'),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认清除'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetSettingsDialog(
    BuildContext context,
    SettingsProvider settings,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.warningColor,
                      AppTheme.warningColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: const Icon(
                  Icons.restore_rounded,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              // 内容
              const Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      '重置所有设置',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '此操作将恢复所有设置到默认值，您的任务数据不会受影响。',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await settings.resetToDefault();
                          _loadSettingsToControllers();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('设置已重置'),
                                backgroundColor: AppTheme.successColor,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.warningColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认重置'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width > 400
              ? 400
              : MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    // 应用Logo
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 应用名称
                    const Text(
                      '智能任务助手',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 版本号
                    Text(
                      '版本 ${settings.appVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // 内容区域 - Flexible + SingleChildScrollView 防止内容溢出
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // AI标识
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'AI 完全编写',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6366F1),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '由 CLI+GLM5 大模型独立完成所有代码开发',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // 功能列表
                        _buildAboutListItem(
                          Icons.psychology_outlined,
                          'AI智能识别',
                          '智能解析任务内容和时间',
                        ),
                        _buildAboutListItem(
                          Icons.notifications_active_outlined,
                          '智能提醒',
                          '多级通知系统，不错过任何任务',
                        ),
                        _buildAboutListItem(
                          Icons.content_copy_outlined,
                          '剪贴板监视',
                          '自动识别粘贴内容',
                        ),
                        _buildAboutListItem(
                          Icons.sync_alt_outlined,
                          '周期任务',
                          '支持日/周/月循环提醒',
                        ),
                        _buildAboutListItem(
                          Icons.repeat_rounded,
                          '习惯追踪',
                          '间隔/固定提醒，打卡与进度管理',
                        ),
                        _buildAboutListItem(
                          Icons.record_voice_over_outlined,
                          '语音提醒',
                          'TTS语音播报与自定义音频文件',
                        ),
                        _buildAboutListItem(
                          Icons.insights_outlined,
                          '任务统计',
                          '多维度数据分析与可视化图表',
                        ),

                        const SizedBox(height: 24),

                        // 技术信息
                        _buildAboutListItem(
                          Icons.code_outlined,
                          '技术栈',
                          'Flutter + Dart 跨平台开发',
                        ),
                        _buildAboutListItem(
                          Icons.person_outline,
                          '开发者',
                          '黄勇',
                        ),
                        _buildAboutListItem(
                          Icons.email_outlined,
                          '联系邮箱',
                          '222582@qq.com',
                        ),
                      ],
                    ),
                  ),
                ), // SingleChildScrollView
              ), // Flexible

              // 底部按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '关闭',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutListItem(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConfigSavedMessage(BuildContext context, AIMode mode) {
    String modeText;
    IconData modeIcon;

    switch (mode) {
      case AIMode.local:
        modeText = '本地规则模式';
        modeIcon = Icons.check_circle_outlined;
        break;
      case AIMode.localLLM:
        modeText = '本地大模型';
        modeIcon = Icons.cloud_outlined;
        break;
      case AIMode.remoteAPI:
        modeText = '远程API服务';
        modeIcon = Icons.cloud_queue_outlined;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(modeIcon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '配置已保存：$modeText',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
