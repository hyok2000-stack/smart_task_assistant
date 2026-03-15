import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../widgets/reminder_action_dialog.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

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
  GlobalKey<NavigatorState>? _navigatorKey;

  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 上次提醒时间（用于控制提醒间隔，避免过于频繁）
  final Map<String, DateTime> _lastReminderTime = {};

  // 稍后提醒的任务（用户选择"稍后提醒"，在指定时间后再次提醒）
  final Map<String, DateTime> _snoozedTasks = {};

  // 持续提醒间隔（秒）- 提醒后隔多少秒再次提醒
  static const int _continualReminderIntervalSeconds = 30;

  /// 初始化提醒服务
  void init(TaskProvider taskProvider, GlobalKey<NavigatorState> navigatorKey) {
    _taskProvider = taskProvider;
    _navigatorKey = navigatorKey;

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

  /// 检查需要提醒的任务
  void _checkReminders() {
    if (_taskProvider == null) {
      debugPrint('⚠️ _checkReminders: _taskProvider 为空');
      return;
    }

    if (_navigatorKey == null) {
      debugPrint('⚠️ _checkReminders: _navigatorKey 为空');
      return;
    }

    final now = DateTime.now();
    debugPrint('===== _checkReminders 开始检查 (${now.toIso8601String()}) =====');
    debugPrint('总任务数: ${_taskProvider!.tasks.length}');

    int checkedCount = 0;
    int needRemindCount = 0;

    for (final task in _taskProvider!.tasks) {
      checkedCount++;

      // 跳过已完成或已取消的任务
      if (task.isCompleted) {
        debugPrint('  [${task.title}] 已完成，跳过');
        continue;
      }

      if (task.status == TaskStatus.cancelled) {
        debugPrint('  [${task.title}] 已取消，跳过');
        continue;
      }

      // 跳过没有截止时间的任务
      if (task.dueTime == null) {
        debugPrint('  [${task.title}] 无截止时间，跳过');
        continue;
      }

      // 跳过已永久关闭提醒的任务
      if (task.reminderDismissed) {
        debugPrint('  [${task.title}] 已永久关闭提醒，跳过');
        continue;
      }

      // 检查是否需要提醒
      final shouldRemind = _shouldShowReminder(task, now);

      if (shouldRemind) {
        needRemindCount++;
        debugPrint('✅ [${task.title}] 需要提醒！');
        debugPrint('   - 截止时间: ${task.dueTime?.toIso8601String()}');
        debugPrint('   - 提醒分钟: ${task.reminderMinutes}');
        debugPrint('   - 当前时间: ${now.toIso8601String()}');
        _showReminder(task);
      } else {
        debugPrint('  [${task.title}] 不需要提醒');
        if (task.reminderMinutes != null && task.dueTime != null) {
          final reminderTime =
              task.dueTime!.subtract(Duration(minutes: task.reminderMinutes!));
          final diff = now.difference(reminderTime);
          debugPrint('   - 提醒时间: ${reminderTime.toIso8601String()}');
          debugPrint('   - 时间差: ${diff.inSeconds}秒');
        }
      }
    }

    debugPrint(
        '===== 检查完成: 已检查 $checkedCount 个任务，需要提醒 $needRemindCount 个 =====');
  }

  /// 判断是否应该显示提醒
  bool _shouldShowReminder(Task task, DateTime now) {
    // 1. 检查是否有稍后提醒设置
    if (_snoozedTasks.containsKey(task.id)) {
      final snoozeTime = _snoozedTasks[task.id]!;
      // 如果稍后提醒时间已到
      if (now.isAfter(snoozeTime)) {
        return true;
      }
      return false;
    }

    // 2. 如果已经提醒过，检查是否需要持续提醒
    if (_lastReminderTime.containsKey(task.id)) {
      final lastTime = _lastReminderTime[task.id]!;
      final nextReminderTime = lastTime.add(
        Duration(seconds: _continualReminderIntervalSeconds),
      );
      // 检查是否到了下次提醒的时间
      if (now.isAfter(nextReminderTime)) {
        return true;
      }
      return false; // 还没到下次提醒时间
    }

    // 3. 检查是否设置了不提醒
    if (task.reminderMinutes == null) {
      // 用户选择了"不提醒"，不触发提醒
      return false;
    }

    // 4. 检查正常的提醒时间
    final reminderMinutes = task.reminderMinutes!;
    final reminderTime =
        task.dueTime!.subtract(Duration(minutes: reminderMinutes));

    // 只要是过了提醒时间，就一直提醒（不再有1小时限制）
    if (now.isAfter(reminderTime)) {
      debugPrint('任务 "${task.title}" 已超过提醒时间，需要提醒');
      return true;
    }

    return false;
  }

  /// 显示提醒
  void _showReminder(Task task) {
    if (_navigatorKey?.currentContext == null) return;

    // 记录上次提醒时间
    _lastReminderTime[task.id] = DateTime.now();

    // 播放声音和振动
    playReminderSound();

    // 显示弹窗
    _showReminderDialog(task);
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
          if (dismissed) {
            // 用户点击"不再提醒" - 永久关闭该任务的提醒
            final updatedTask = task.copyWith(reminderDismissed: true);
            await _taskProvider!.updateTask(updatedTask);

            // 清除提醒状态
            _lastReminderTime.remove(task.id);
            _snoozedTasks.remove(task.id);

            debugPrint('任务 "${task.title}" 已设置为不再提醒');
          } else if (reminderMinutes != null) {
            // 用户选择修改提醒时间 - 更新任务的提醒时间
            final updatedTask = task.copyWith(reminderMinutes: reminderMinutes);
            await _taskProvider!.updateTask(updatedTask);

            // 清除提醒状态，等待新的提醒时间
            _lastReminderTime.remove(task.id);
            _snoozedTasks.remove(task.id);

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
              Duration(seconds: _continualReminderIntervalSeconds),
            );
            _lastReminderTime.remove(task.id);
            debugPrint(
                '任务 "${task.title}" 将在 $_continualReminderIntervalSeconds 秒后再次提醒');
          }
        },
      ),
    );
  }

  /// 清除任务的提醒状态（用于任务被修改或删除时）
  void clearReminderState(String taskId) {
    _lastReminderTime.remove(taskId);
    _snoozedTasks.remove(taskId);
  }

  /// 释放资源
  void dispose() {
    stopChecking();
    _audioPlayer.dispose();
    _lastReminderTime.clear();
    _snoozedTasks.clear();
  }
}
