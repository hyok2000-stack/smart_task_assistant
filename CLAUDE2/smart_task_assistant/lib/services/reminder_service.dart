import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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

  // 重复提醒间隔（毫秒）
  static const int _voiceReminderIntervalMs = 60000; // 1分钟

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

  // 当前显示的提醒（避免重复弹出）
  String? _currentShowingReminderId;
  String? _currentShowingReminderType; // 'task' or 'habit'

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

    // 打印所有任务的提醒设置
    for (final task in taskProvider.tasks) {
      debugPrint('任务: ${task.title}, 提醒分钟: ${task.reminderMinutes}, 截止时间: ${task.dueTime}, 已完成: ${task.isCompleted}');
    }

    // 打印所有习惯的提醒设置
    for (final habit in habitProvider.habits) {
      debugPrint('习惯: ${habit.title}, 启用: ${habit.isEnabled}, 间隔: ${habit.intervalMinutes}, 固定时间: ${habit.fixedTime}');
    }

    // 更新 HabitService 的习惯列表缓存
    _habitService.updateHabits(habitProvider.habits);

    // 启动定时检查
    startChecking();

    debugPrint('提醒服务已初始化');
  }

  /// 播放提醒声音和振动
  void playReminderSound() async {
    debugPrint('===== 开始播放提醒声音 =====');

    if (kIsWeb) {
      playReminderSoundWeb();
    } else {
      try {
        // 先振动提醒（这个比较可靠）
        if (await Vibration.hasVibrator()) {
          debugPrint('设备支持振动');
          // 连续振动三次,每次振动300ms,间隔100ms
          if (await Vibration.hasAmplitudeControl()) {
            await Vibration.vibrate(
                pattern: [0, 300, 100, 300, 100, 300], amplitude: 255);
            debugPrint('已触发振动（带振幅控制）');
          } else {
            await Vibration.vibrate(pattern: [0, 300, 100, 300, 100, 300]);
            debugPrint('已触发振动（不带振幅控制）');
          }
        } else {
          debugPrint('设备不支持振动');
        }

        // 尝试播放声音
        bool soundPlayed = false;

        // 方法1：尝试播放Asset文件
        try {
          await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
          soundPlayed = true;
          debugPrint('✓ 成功播放Asset提示音');
        } catch (e) {
          debugPrint('✗ Asset提示音文件不存在: $e');

          // 方法2：尝试播放UrlSource（使用内置提示音）
          try {
            // 使用一个简短的提示音URL（来自免费音效库）
            await _audioPlayer.play(UrlSource(
                'https://www.soundjay.com/buttons/sounds/button-09a.mp3'));
            soundPlayed = true;
            debugPrint('✓ 成功播放网络提示音');
          } catch (e2) {
            debugPrint('✗ 网络提示音播放失败: $e2');

            // 方法3：使用系统提示音
            try {
              await _audioPlayer.play(DeviceFileSource(
                  '/system/media/audio/alarms/Alarm_Classic.ogg'));
              soundPlayed = true;
              debugPrint('✓ 成功播放系统提示音');
            } catch (e3) {
              debugPrint('✗ 系统提示音播放失败: $e3');
            }
          }
        }

        if (!soundPlayed) {
          debugPrint('⚠ 所有提示音播放方式都失败了，但振动已触发');
        }

        debugPrint('===== 提醒播放完成 =====');
      } catch (e) {
        debugPrint('播放提醒声音时发生错误: $e');
        debugPrint('===== 提醒播放出错 =====');
      }
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
    // 注意：Flutter 层始终执行提醒检查
    // 当 App 在后台时，native 层也会检查并通过 FullScreenActivity 显示提醒
    // 两层都检查可以确保提醒不会遗漏

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
    debugPrint('');
    debugPrint('===== _checkReminders 开始检查 (${now.toIso8601String()}) =====');
    debugPrint('总任务数: ${_taskProvider!.tasks.length}');
    debugPrint('总习惯数: ${_habitProvider!.habits.length}');

    // 打印所有任务的提醒状态（调试用）
    debugPrint('===== 任务提醒状态概览 =====');
    for (final task in _taskProvider!.tasks) {
      if (!task.isCompleted &&
          task.status != TaskStatus.cancelled &&
          task.dueTime != null &&
          task.reminderMinutes != null &&
          !task.reminderDismissed) {
        final reminderTime = task.dueTime!.subtract(Duration(minutes: task.reminderMinutes!));
        final isPastDue = now.isAfter(reminderTime);
        final hasFirstSent = _firstReminderSent.contains(task.id);
        debugPrint('  ${task.title}: 提醒时间=${reminderTime.toIso8601String()}, 已过提醒=$isPastDue, 首次提醒已发送=$hasFirstSent');
      }
    }
    debugPrint('============================');

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

    debugPrint('');
    debugPrint('===== 任务提醒详细检查 =====');

    // 先列出所有有提醒设置且未完成的任务
    debugPrint('所有有提醒设置且未完成的任务:');
    for (final task in _taskProvider!.tasks) {
      if (!task.isCompleted &&
          task.status != TaskStatus.cancelled &&
          task.dueTime != null &&
          task.reminderMinutes != null &&
          !task.reminderDismissed) {
        final reminderTime = task.dueTime!.subtract(Duration(minutes: task.reminderMinutes!));
        final isPast = now.isAfter(reminderTime);
        debugPrint('  - ${task.title}: 截止=${task.dueTime?.toIso8601String()}, 提醒${task.reminderMinutes}分钟, 提醒时间=${reminderTime.toIso8601String()}, 已过=$isPast');
      }
    }
    debugPrint('============================');

    for (final task in _taskProvider!.tasks) {
      checkedCount++;

      // 跳过已完成或已取消的任务
      if (task.isCompleted) {
        debugPrint('  [任务] ${task.title} 已完成，跳过');
        continue;
      }

      if (task.status == TaskStatus.cancelled) {
        debugPrint('  [任务] ${task.title} 已取消，跳过');
        continue;
      }

      // 跳过没有截止时间的任务
      if (task.dueTime == null) {
        debugPrint('  [任务] ${task.title} 无截止时间，跳过');
        continue;
      }

      // 跳过已永久关闭提醒的任务
      if (task.reminderDismissed) {
        debugPrint('  [任务] ${task.title} 已永久关闭提醒，跳过');
        continue;
      }

      // 跳过没有设置提醒时间的任务
      if (task.reminderMinutes == null) {
        debugPrint('  [任务] ${task.title} 未设置提醒时间，跳过');
        continue;
      }

      // 检查是否需要提醒
      final shouldRemind = _shouldShowReminder(task, now);

      if (shouldRemind) {
        needRemindCount++;
        debugPrint('✅ [任务] ${task.title} 需要提醒！');
        debugPrint('   - 截止时间: ${task.dueTime?.toIso8601String()}');
        debugPrint('   - 提醒分钟: ${task.reminderMinutes}');
        debugPrint('   - 当前时间: ${now.toIso8601String()}');
        _showTaskReminder(task);
      } else {
        debugPrint('  [任务] ${task.title} 不需要提醒');
        final reminderTime = task.dueTime!.subtract(Duration(minutes: task.reminderMinutes!));
        final diff = now.difference(reminderTime);
        debugPrint('   - 提醒时间: ${reminderTime.toIso8601String()}');
        debugPrint('   - 时间差: ${diff.inSeconds}秒');
      }
    }

    debugPrint('===== 任务检查完成: 已检查 $checkedCount 个任务，需要提醒 $needRemindCount 个 =====');
  }

  /// 检查习惯提醒
  void _checkHabitReminders(DateTime now) {
    if (_habitProvider == null) return;

    int checkedCount = 0;
    int needRemindCount = 0;

    debugPrint('');
    debugPrint('===== 习惯提醒状态概览 =====');
    for (final habit in _habitProvider!.habits) {
      if (habit.isEnabled) {
        debugPrint('  ${habit.title}: triggerType=${habit.triggerType}, interval=${habit.intervalMinutes}, fixed=${habit.fixedTime}');
      }
    }
    debugPrint('============================');

    for (final habit in _habitProvider!.habits) {
      checkedCount++;

      // 跳过未启用的习惯
      if (!habit.isEnabled) {
        debugPrint('  [习惯] ${habit.title} 未启用，跳过');
        continue;
      }

      // 检查是否应该触发提醒
      final shouldRemind = _habitService.shouldTriggerReminder(habit, now);

      if (shouldRemind) {
        needRemindCount++;
        debugPrint('✅ [习惯] ${habit.title} 需要提醒！');
        debugPrint('   - 触发类型: ${habit.triggerType}');
        debugPrint('   - 间隔时间: ${habit.intervalMinutes}');
        debugPrint('   - 固定时间: ${habit.fixedTime}');
        debugPrint('   - 当前时间: ${now.toIso8601String()}');
        _showHabitReminder(habit);
      } else {
        debugPrint('  [习惯] ${habit.title} 不需要提醒');
      }
    }

    debugPrint('===== 习惯检查完成: 已检查 $checkedCount 个习惯，需要提醒 $needRemindCount 个 =====');
  }

  /// 判断是否应该显示提醒
  bool _shouldShowReminder(Task task, DateTime now) {
    debugPrint('  [检查任务] ${task.title}');
    debugPrint('    - 截止时间: ${task.dueTime}');
    debugPrint('    - 提醒分钟: ${task.reminderMinutes}');
    debugPrint('    - 已永久关闭提醒: ${task.reminderDismissed}');
    debugPrint('    - 是否已完成: ${task.isCompleted}');
    debugPrint('    - 是否已发送首次提醒: ${_firstReminderSent.contains(task.id)}');

    // 1. 检查是否有稍后提醒设置
    if (_snoozedTasks.containsKey(task.id)) {
      final snoozeTime = _snoozedTasks[task.id]!;
      final diff = now.difference(snoozeTime);
      debugPrint('    - 有稍后提醒设置，时间: $snoozeTime');
      debugPrint('    - 距离稍后提醒时间: ${diff.inSeconds}秒');
      // 如果稍后提醒时间已到
      if (now.isAfter(snoozeTime)) {
        debugPrint('    → 稍后提醒时间已到，需要提醒');
        return true;
      }
      debugPrint('    → 稍后提醒时间未到，跳过');
      return false;
    }

    // 2. 检查正常的提醒时间（首次提醒）
    if (!_firstReminderSent.contains(task.id)) {
      // 首次提醒检查
      if (task.reminderMinutes == null) {
        debugPrint('    → 未设置提醒时间，跳过');
        return false;
      }

      if (task.dueTime == null) {
        debugPrint('    → 无截止时间，跳过');
        return false;
      }

      final reminderMinutes = task.reminderMinutes!;
      final reminderTime =
          task.dueTime!.subtract(Duration(minutes: reminderMinutes));

      debugPrint('    - 提醒时间: $reminderTime');
      final diff = now.difference(reminderTime);
      debugPrint('    - 距离提醒时间: ${diff.inSeconds}秒');

      // 已超过提醒时间，需要首次提醒
      if (now.isAfter(reminderTime)) {
        debugPrint('    → 已超过提醒时间，需要首次提醒');
        return true;
      }

      debugPrint('    → 还未到提醒时间，跳过');
      return false;
    }

    // 3. 已发送首次提醒，检查是否需要持续提醒
    if (_lastReminderTime.containsKey(task.id)) {
      final lastTime = _lastReminderTime[task.id]!;
      final nextReminderTime = lastTime.add(
        const Duration(seconds: _continualReminderIntervalSeconds),
      );
      final diff = now.difference(nextReminderTime);
      debugPrint('    - 上次提醒时间: $lastTime');
      debugPrint('    - 下次提醒时间: $nextReminderTime');
      debugPrint('    - 距离下次提醒: ${diff.inSeconds}秒');
      // 检查是否到了下次提醒的时间
      if (now.isAfter(nextReminderTime)) {
        debugPrint('    → 持续提醒时间已到（$_continualReminderIntervalSeconds秒间隔）');
        return true;
      }
      debugPrint('    → 持续提醒时间未到，跳过');
      return false;
    }

    debugPrint('    → 无需提醒');
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
      _habitService.speak(
        _habitService.getVoiceText(habit, true),
        voiceType: habit.voiceType,
        voiceStyle: habit.voiceStyle,
        speed: habit.voiceSpeed,
        customVoicePath: habit.customVoicePath,
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
            // 用户选择修改提醒时间 - 更新任务的提醒时间
            final updatedTask = task.copyWith(reminderMinutes: reminderMinutes);
            await _taskProvider!.updateTask(updatedTask);

            // 清除提醒状态，等待新的提醒时间
            _lastReminderTime.remove(task.id);
            _snoozedTasks.remove(task.id);
            _firstReminderSent.remove(task.id); // 重置首次提醒标记

            debugPrint('任务 "${task.title}" 的提醒时间已修改为 $reminderMinutes 分钟前');
          } else if (snoozeMinutes != null) {
            // 用户选择稍后提醒 - 设置稍后提醒时间（不修改任务）
            _snoozedTasks[task.id] =
                DateTime.now().add(Duration(minutes: snoozeMinutes));
            _lastReminderTime.remove(task.id); // 允许稍后再次提醒

            debugPrint('任务 "${task.title}" 将在 $snoozeMinutes 分钟后再次提醒');
          } else {
            // 用户只是关闭窗口 - 设置为稍后持续提醒
            _snoozedTasks[task.id] = DateTime.now().add(
              const Duration(seconds: _continualReminderIntervalSeconds),
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
}
