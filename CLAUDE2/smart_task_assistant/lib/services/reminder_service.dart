import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../providers/habit_provider.dart';
import '../models/habit.dart';
import '../widgets/reminder_action_dialog.dart';
import '../widgets/habit_reminder_dialog.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'tts_service.dart';
import 'habit_service.dart';

// Web 平台的条件导入
import 'reminder_service_web.dart'
    if (dart.library.io) 'reminder_service_stub.dart';

/// 提醒服务 - 负责任务提醒的检查、声音播放和弹窗显示
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  Timer? _checkTimer;
  TaskProvider? _taskProvider;
  HabitProvider? _habitProvider;
  GlobalKey<NavigatorState>? _navigatorKey;

  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

  // TTS 服务实例
  final TTSService _ttsService = TTSService();

  // HabitService 实例
  final HabitService _habitService = HabitService();

  // 语音提醒状态追踪（避免重复播放）
  final Map<String, DateTime> _lastVoiceReminderTime = {};

  // 重复提醒间隔（毫秒）- 与持续提醒间隔对齐，确保每次提醒都播语音
  static const int _voiceReminderIntervalMs = 30000; // 30秒

  // 上次提醒时间（用于控制提醒间隔，避免过于频繁）
  final Map<String, DateTime> _lastReminderTime = {};

  // 首次提醒标记（用于区分首次提醒和持续提醒）
  final Set<String> _firstReminderSent = {};

  // 习惯上次提醒时间
  final Map<String, DateTime> _lastHabitReminderTime = {};

  // 稍后提醒的任务（用户选择"稍后提醒"，在指定时间后再次提醒）
  final Map<String, DateTime> _snoozedTasks = {};

  // 持续提醒间隔（秒）- 提醒后隔多少秒再次提醒
  static const int _continualReminderIntervalSeconds = 30;

  // 逾期任务持续提醒间隔（秒）- 逾期任务每隔多少秒再次提醒
  static const int _overdueReminderIntervalSeconds = 180; // 3分钟

  // 当前显示的提醒（避免重复弹出）
  String? _currentShowingReminderId;
  String? _currentShowingReminderType; // 'task' or 'habit'
  static const bool _verboseReminderLogs = false;

  /// 初始化提醒服务
  void init(
    TaskProvider taskProvider,
    HabitProvider habitProvider,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    // 先停止现有的检查，避免重复初始化导致内存泄漏
    stopChecking();

    _taskProvider = taskProvider;
    _habitProvider = habitProvider;
    _navigatorKey = navigatorKey;

    debugPrint('===== ReminderService.init =====');
    debugPrint('TaskProvider 任务数量: ${taskProvider.tasks.length}');
    debugPrint('HabitProvider 习惯数量: ${habitProvider.habits.length}');

    if (_verboseReminderLogs) {
      for (final task in taskProvider.tasks) {
        debugPrint('任务: ${task.title}, 提醒分钟: ${task.reminderMinutes}, 截止时间: ${task.dueTime}, 已完成: ${task.isCompleted}');
      }

      for (final habit in habitProvider.habits) {
        debugPrint('习惯: ${habit.title}, 启用: ${habit.isEnabled}, 间隔: ${habit.intervalMinutes}, 固定时间: ${habit.fixedTime}');
      }
    }
    // 更新 HabitService 的习惯列表缓存
    _habitService.updateHabits(habitProvider.habits);

    // 启动定时检查
    startChecking();

    debugPrint('提醒服务已初始化');
  }

  /// 播放提醒声音和振动
  void playReminderSound() async {
    if (kIsWeb) {
      playReminderSoundWeb();
      return;
    }

    try {
      if (await Vibration.hasVibrator()) {
        if (await Vibration.hasAmplitudeControl()) {
          await Vibration.vibrate(
            pattern: [0, 300, 100, 300, 100, 300],
            amplitude: 255,
          );
        } else {
          await Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
        }
      }

      if (await _tryPlayAssetSound()) {
        return;
      }

      debugPrint('No bundled reminder sound was available');
    } catch (e) {
      debugPrint('Failed to play reminder sound: $e');
    }
  }

  Future<bool> _tryPlayAssetSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 启动定时检查
  void startChecking() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      const Duration(seconds: 10), // 每10秒检查一次
      (_) => _checkReminders(),
    );
    debugPrint('提醒检查已启动');
  }

  /// 停止定时检查
  void stopChecking() {
    _checkTimer?.cancel();
    _checkTimer = null;
    debugPrint('提醒检查已停止');
  }

  /// 检查需要提醒的任务和习惯
  void _checkReminders() {
    // APP 在后台时，Flutter 层跳过提醒检查，由原生服务全权处理
    // 原因：flutter_tts 在 Activity 暂停时无法发声，
    // 且 Flutter 层更新状态会导致提醒被"吞掉"而原生层不再触发
    if (!isAppForeground) {
      return;
    }

    // 屏幕关闭时跳过 Flutter 层检查，由原生层全权处理
    // Flutter TTS 引擎在屏幕关闭时暂停，无法播放语音
    _updateScreenState();
    if (!_isScreenOn) {
      return;
    }

    if (_taskProvider == null) {
      debugPrint('⚠️ _checkReminders: _taskProvider 为空');
      return;
    }

    if (_habitProvider == null) {
      debugPrint('⚠️ _checkReminders: _habitProvider 为空');
      return;
    }

    if (_navigatorKey == null) {
      debugPrint('⚠️ _checkReminders: _navigatorKey 为空');
      return;
    }

    final now = DateTime.now();
    if (_verboseReminderLogs) {
      debugPrint('');
      debugPrint('===== _checkReminders started (${now.toIso8601String()}) =====');
      debugPrint('Task count: ${_taskProvider!.tasks.length}');
      debugPrint('Habit count: ${_habitProvider!.habits.length}');

      for (final task in _taskProvider!.tasks) {
        if (!task.isCompleted &&
            task.status != TaskStatus.cancelled &&
            task.dueTime != null &&
            task.reminderMinutes != null &&
            !task.reminderDismissed) {
          final reminderTime = task.dueTime!.subtract(
            Duration(minutes: task.reminderMinutes!),
          );
          final isPastDue = now.isAfter(reminderTime);
          final hasFirstSent = _firstReminderSent.contains(task.id);
          debugPrint(
            'Reminder candidate: ${task.title}, reminderTime=${reminderTime.toIso8601String()}, pastDue=$isPastDue, firstSent=$hasFirstSent',
          );
        }
      }
    }

    // 检查任务提醒
    _checkTaskReminders(now);

    // 检查习惯提醒
    _checkHabitReminders(now);

    debugPrint('===== _checkReminders 检查完成 =====');
  }

  /// 检查任务提醒
  void _checkTaskReminders(DateTime now) {
    int checkedCount = 0;
    int needRemindCount = 0;

    for (final task in _taskProvider!.tasks) {
      checkedCount++;

      // 跳过已完成或已取消的任务
      if (task.isCompleted) continue;
      if (task.status == TaskStatus.cancelled) continue;
      if (task.dueTime == null) continue;
      if (task.reminderDismissed) continue;
      if (task.reminderMinutes == null) continue;

      // 检查是否需要提醒
      final shouldRemind = _shouldShowReminder(task, now);

      if (shouldRemind) {
        needRemindCount++;
        debugPrint('[任务提醒] "${task.title}" 需要提醒 (截止: ${task.dueTime?.toIso8601String()}, 提前${task.reminderMinutes}分钟)');
        _showTaskReminder(task);
      }
    }

    if (checkedCount > 0) {
      debugPrint('[任务检查] 已检查 $checkedCount 个，需要提醒 $needRemindCount 个');
    }
  }

  /// 检查习惯提醒
  void _checkHabitReminders(DateTime now) {
    if (_habitProvider == null) return;

    int checkedCount = 0;
    int needRemindCount = 0;

    for (final habit in _habitProvider!.habits) {
      checkedCount++;

      // 跳过未启用的习惯
      if (!habit.isEnabled) continue;

      // 检查是否应该触发提醒
      final shouldRemind = _habitService.shouldTriggerReminder(habit, now);

      if (shouldRemind) {
        needRemindCount++;
        debugPrint('[习惯提醒] "${habit.title}" 需要提醒 (类型: ${habit.triggerType}, 间隔: ${habit.intervalMinutes}分钟)');
        _showHabitReminder(habit);
      }
    }

    if (checkedCount > 0) {
      debugPrint('[习惯检查] 已检查 $checkedCount 个，需要提醒 $needRemindCount 个');
    }
  }

  /// 判断是否应该显示提醒
  bool _shouldShowReminder(Task task, DateTime now) {
    // 1. 检查是否有稍后提醒设置
    if (_snoozedTasks.containsKey(task.id)) {
      final snoozeTime = _snoozedTasks[task.id]!;
      if (now.isAfter(snoozeTime)) {
        debugPrint('[提醒判断] "${task.title}" 稍后提醒时间已到');
        return true;
      }
      return false;
    }

    // 2. 检查正常的提醒时间（首次提醒）
    if (!_firstReminderSent.contains(task.id)) {
      if (task.reminderMinutes == null || task.dueTime == null) {
        return false;
      }

      final reminderTime =
          task.dueTime!.subtract(Duration(minutes: task.reminderMinutes!));

      if (now.isAfter(reminderTime)) {
        return true;
      }
      return false;
    }

    // 3. 已发送首次提醒，检查是否需要持续提醒
    if (_lastReminderTime.containsKey(task.id)) {
      final lastTime = _lastReminderTime[task.id]!;
      final interval = task.isOverdue
          ? const Duration(seconds: _overdueReminderIntervalSeconds)
          : const Duration(seconds: _continualReminderIntervalSeconds);
      final nextReminderTime = lastTime.add(interval);

      if (now.isAfter(nextReminderTime)) {
        return true;
      }
      return false;
    }

    // 4. 逾期任务兜底：任务已逾期且有提醒设置，但状态丢失时（如 app 重启后
    //    _lastReminderTime 和 _snoozedTasks 为空），继续提醒直到用户关闭
    if (task.isOverdue && task.reminderMinutes != null) {
      return true;
    }

    return false;
  }

  /// 显示任务提醒
  void _showTaskReminder(Task task) {
    if (_navigatorKey?.currentContext == null) return;

    // 如果已有提醒正在显示/播放，先停止当前的声音和语音
    if (_currentShowingReminderId != null) {
      debugPrint('⚠️ 已有提醒弹窗显示中（$_currentShowingReminderType），停止当前提醒音乐，切换到任务 "${task.title}"');
      _stopCurrentReminderPlayback();
      _dismissCurrentDialog();
    }

    debugPrint('===== 显示任务提醒: ${task.title} =====');

    // 标记首次提醒已发送
    if (!_firstReminderSent.contains(task.id)) {
      _firstReminderSent.add(task.id);
      debugPrint('标记首次提醒已发送: ${task.id}');
    }

    // 记录上次提醒时间
    _lastReminderTime[task.id] = DateTime.now();
    _currentShowingReminderId = task.id;
    _currentShowingReminderType = 'task';

    debugPrint('记录提醒时间: $_lastReminderTime[task.id]');
    debugPrint('下次提醒时间将在 ${_lastReminderTime[task.id]!.add(const Duration(seconds: _continualReminderIntervalSeconds))}');

    // 播放声音和振动
    playReminderSound();

    // 播放语音提醒
    _playVoiceReminder(task);

    // 显示弹窗
    _showReminderDialog(task);
  }

  /// 停止当前提醒的声音和语音播放
  void _stopCurrentReminderPlayback() {
    debugPrint('===== 停止当前提醒播放 =====');
    // 停止语音播报
    _ttsService.stopSpeaking();
    // 停止提醒声音
    _audioPlayer.stop();
  }

  /// 关闭当前正在显示的提醒对话框
  void _dismissCurrentDialog() {
    if (_currentShowingReminderId == null) return;

    final context = _navigatorKey?.currentContext;
    if (context != null && Navigator.canPop(context)) {
      debugPrint('关闭当前提醒对话框: $_currentShowingReminderId');
      Navigator.pop(context);
    }
    _currentShowingReminderId = null;
    _currentShowingReminderType = null;
  }

  /// 显示习惯提醒
  void _showHabitReminder(Habit habit) {
    if (_navigatorKey?.currentContext == null) return;

    final now = DateTime.now();

    // 记录上次提醒时间（避免重复提醒）
    if (_lastHabitReminderTime.containsKey(habit.id)) {
      final lastTime = _lastHabitReminderTime[habit.id]!;
      final diff = now.difference(lastTime);
      // 1分钟内不重复提醒
      if (diff.inSeconds < 60) {
        debugPrint('习惯 "${habit.title}" 1分钟内已提醒过，跳过');
        return;
      }
    }

    // 如果已有提醒正在显示/播放，先停止当前的声音和语音
    if (_currentShowingReminderId != null) {
      debugPrint('⚠️ 已有提醒弹窗显示中（$_currentShowingReminderType），停止当前提醒音乐，切换到习惯 "${habit.title}"');
      _stopCurrentReminderPlayback();
      _dismissCurrentDialog();
    }

    _lastHabitReminderTime[habit.id] = DateTime.now();
    _currentShowingReminderId = habit.id;
    _currentShowingReminderType = 'habit';

    // 播放声音
    if (habit.soundEnabled) {
      playReminderSound();
    }

    // 播放振动
    if (habit.vibrationEnabled) {
      _playVibration();
    }

    // 播放语音
    if (habit.voiceEnabled) {
      // 防御性检查：只有 voiceType 为 'custom' 且路径有效时才传递自定义语音路径
      String? effectiveVoiceType = habit.voiceType;
      String? effectiveCustomVoicePath = habit.customVoicePath;
      if (effectiveVoiceType == 'custom') {
        if (effectiveCustomVoicePath == null || effectiveCustomVoicePath.isEmpty) {
          debugPrint('⚠️ 习惯语音类型为自定义，但路径为空，回退到 TTS 播放');
          effectiveVoiceType = 'neutral';
          effectiveCustomVoicePath = null;
        }
      } else {
        effectiveCustomVoicePath = null;
      }

      _habitService.speak(
        _habitService.getVoiceText(habit, true),
        voiceType: effectiveVoiceType,
        voiceStyle: habit.voiceStyle,
        speed: habit.voiceSpeed,
        customVoicePath: effectiveCustomVoicePath,
      );
    }

    // 显示弹窗
    _showHabitReminderDialog(habit);
  }

  /// 播放振动
  void _playVibration() async {
    try {
      if (await Vibration.hasVibrator()) {
        if (await Vibration.hasAmplitudeControl()) {
          await Vibration.vibrate(
              pattern: [0, 300, 100, 300, 100, 300], amplitude: 255);
        } else {
          await Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
        }
      }
    } catch (e) {
      debugPrint('振动播放失败: $e');
    }
  }

  /// 显示提醒对话框
  void _showReminderDialog(Task task) {
    final context = _navigatorKey!.currentContext!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ReminderActionDialog(
        task: task,
        onAction: (
            {int? reminderMinutes,
            bool dismissed = false,
            int? snoozeMinutes}) async {
          // 清除当前显示的提醒标记
          _currentShowingReminderId = null;
          _currentShowingReminderType = null;

          if (dismissed) {
            // 用户点击"不再提醒" - 永久关闭该任务的提醒
            final updatedTask = task.copyWith(reminderDismissed: true);
            await _taskProvider!.updateTask(updatedTask);

            // 清除提醒状态
            _lastReminderTime.remove(task.id);
            _snoozedTasks.remove(task.id);
            _firstReminderSent.remove(task.id);

            debugPrint('任务 "${task.title}" 已设置为不再提醒');
          } else if (reminderMinutes != null) {
            // 用户选择修改提醒时间 - 更新任务的提醒时间，并清除"不再提醒"状态
            final updatedTask = task.copyWith(
              reminderMinutes: reminderMinutes,
              reminderDismissed: false,
            );
            await _taskProvider!.updateTask(updatedTask);

            // 清除提醒状态
            _lastReminderTime.remove(task.id);
            _snoozedTasks.remove(task.id);
            _firstReminderSent.remove(task.id);

            // 如果同时传了 snoozeMinutes，设置稍后提醒
            if (snoozeMinutes != null) {
              final snoozeUntil =
                  DateTime.now().add(Duration(minutes: snoozeMinutes));
              _snoozedTasks[task.id] = snoozeUntil;
              await _syncNativeSnooze(
                task.id,
                snoozeMinutes,
                snoozeUntil: snoozeUntil,
              );
              debugPrint('任务 "${task.title}" 提醒时间已修改为 $reminderMinutes 分钟前，$snoozeMinutes 分钟后再次提醒');
            } else {
              debugPrint('任务 "${task.title}" 的提醒时间已修改为 $reminderMinutes 分钟前');
            }
          } else if (snoozeMinutes != null) {
            // 用户选择稍后提醒 - 设置稍后提醒时间（不修改任务）
            final snoozeUntil =
                DateTime.now().add(Duration(minutes: snoozeMinutes));
            _snoozedTasks[task.id] = snoozeUntil;
            await _syncNativeSnooze(
              task.id,
              snoozeMinutes,
              snoozeUntil: snoozeUntil,
            );
            // 如果任务之前被标记为不再提醒，恢复提醒
            if (task.reminderDismissed) {
              final updatedTask = task.copyWith(reminderDismissed: false);
              await _taskProvider!.updateTask(updatedTask);
            }
            _lastReminderTime.remove(task.id); // 允许稍后再次提醒

            debugPrint('任务 "${task.title}" 将在 $snoozeMinutes 分钟后再次提醒');
          } else {
            // 用户只是关闭窗口 - 设置为稍后持续提醒
            final snoozeUntil = DateTime.now().add(
              const Duration(seconds: _continualReminderIntervalSeconds),
            );
            _snoozedTasks[task.id] = snoozeUntil;
            await _syncNativeSnooze(
              task.id,
              1,
              snoozeUntil: snoozeUntil,
            );
            _lastReminderTime.remove(task.id);
            debugPrint(
                '任务 "${task.title}" 将在 $_continualReminderIntervalSeconds 秒后再次提醒');
          }
        },
      ),
    ).then((_) {
      // 对话框关闭时也要清除标记（防止用户按返回键关闭）
      _currentShowingReminderId = null;
      _currentShowingReminderType = null;
    });
  }

  /// 显示习惯提醒对话框
  void _showHabitReminderDialog(Habit habit) {
    final context = _navigatorKey!.currentContext!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => HabitReminderDialog(
        habit: habit,
      ),
    ).then((_) {
      // 对话框关闭时清除标记
      _currentShowingReminderId = null;
      _currentShowingReminderType = null;
    });
  }

  /// 播放语音提醒
  void _playVoiceReminder(Task task) {
    // 检查是否启用语音提醒
    if (!task.reminderVoiceEnabled) {
      debugPrint('任务 "${task.title}" 未启用语音提醒');
      return;
    }

    // 调试日志：输出任务的语音设置，便于排查自定义语音误播放问题
    debugPrint('任务 "${task.title}" 语音设置: voiceType=${task.reminderVoiceType}, customPath=${task.reminderCustomVoicePath}');

    // 检查是否在重复提醒间隔内（避免过于频繁）
    if (_lastVoiceReminderTime.containsKey(task.id)) {
      final lastTime = _lastVoiceReminderTime[task.id]!;
      final diff = DateTime.now().difference(lastTime);
      if (diff.inMilliseconds < _voiceReminderIntervalMs) {
        debugPrint('任务 "${task.title}" 语音提醒间隔未到，跳过（距离上次 ${diff.inSeconds}秒）');
        return;
      }
    }

    // 记录语音提醒时间
    _lastVoiceReminderTime[task.id] = DateTime.now();

    // 播放语音（await 确保初始化完成后再播报）
    _ttsService.speakForTaskReminder(task, isRepeat: false).then((_) {
      debugPrint('✓ 任务 "${task.title}" 语音提醒播放完成');
    }).catchError((e) {
      debugPrint('✗ 任务 "${task.title}" 语音提醒播放失败: $e');
    });
  }

  /// 清除任务的提醒状态（用于任务被修改或删除时）
  void clearReminderState(String taskId) {
    debugPrint('===== clearReminderState: $taskId =====');
    debugPrint('  - 移除 _lastReminderTime: ${_lastReminderTime.remove(taskId)}');
    debugPrint('  - 移除 _snoozedTasks: ${_snoozedTasks.remove(taskId)}');
    debugPrint('  - 移除 _lastVoiceReminderTime: ${_lastVoiceReminderTime.remove(taskId)}');
    debugPrint('  - 移除 _firstReminderSent: ${_firstReminderSent.remove(taskId)}');

    // 打印当前所有提醒状态
    debugPrint('  当前提醒状态数量:');
    debugPrint('    - _lastReminderTime: ${_lastReminderTime.length}');
    debugPrint('    - _firstReminderSent: ${_firstReminderSent.length}');
  }

  /// 清除习惯的提醒状态（用于习惯被修改时）
  void clearHabitReminderState(String habitId) {
    debugPrint('===== clearHabitReminderState: $habitId =====');
    debugPrint('  - 移除 _lastHabitReminderTime: ${_lastHabitReminderTime.remove(habitId)}');

    // 打印当前所有习惯提醒状态
    debugPrint('  当前习惯提醒状态数量: ${_lastHabitReminderTime.length}');
  }

  /// 释放资源
  void dispose() {
    stopChecking();
    _audioPlayer.dispose();
    _lastReminderTime.clear();
    _snoozedTasks.clear();
  }

  // --- Native bridge integration ---

  /// App 是否在前台（前台时由 Flutter 层处理提醒，后台时由 Kotlin 层处理）
  bool isAppForeground = true;

  // 屏幕状态缓存（由原生层 isScreenOn 查询更新）
  static const _reminderChannel =
      MethodChannel('com.smarttask.smart_task_assistant/reminder');
  bool _isScreenOn = true;
  DateTime _lastScreenCheck = DateTime.fromMillisecondsSinceEpoch(0);

  /// 标记提醒已由原生层显示（避免 Flutter 层重复弹窗）
  void markShown(String id) {
    _lastReminderTime[id] = DateTime.now();
    _firstReminderSent.add(id);
    debugPrint('Reminder marked as shown by native layer: $id');
  }

  /// 设置稍后提醒（由原生层 FullScreenActivity 触发）
  void setSnooze(String id, int minutes) {
    _snoozedTasks[id] = DateTime.now().add(Duration(minutes: minutes));
    debugPrint('Reminder snoozed from native layer: $id for $minutes minutes');
  }

  Future<void> _syncNativeSnooze(
    String id,
    int minutes, {
    DateTime? snoozeUntil,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _reminderChannel.invokeMethod('snoozeReminder', {
        'id': id,
        'minutes': minutes,
        if (snoozeUntil != null)
          'snoozeUntil': snoozeUntil.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Failed to sync native snooze: $e');
    }
  }

  /// 从原生层查询屏幕状态（每 5 秒最多查一次，避免频繁调用）
  void _updateScreenState() {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (now.difference(_lastScreenCheck).inSeconds < 5) return;
    _lastScreenCheck = now;
    _reminderChannel.invokeMethod<bool>('isScreenOn').then((on) {
      if (on != null) _isScreenOn = on;
    }).catchError((_) {});
  }
}
