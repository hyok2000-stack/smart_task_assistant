import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../database/database_helper.dart';
import '../services/habit_service.dart';

/// 习惯状态管理
class HabitProvider extends ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final HabitService _habitService = HabitService();

  // 提醒状态清除回调
  Function(String habitId)? onReminderReset;

  // Native reminder data change notification
  static const _reminderChannel =
      MethodChannel('com.smarttask.smart_task_assistant/reminder');

  void _notifyNativeDataChanged(String type, [String? id]) {
    if (!Platform.isAndroid) return;
    try {
      _reminderChannel
          .invokeMethod('notifyDataChanged', {'type': type, 'id': id});
    } catch (_) {}
  }

  List<Habit> _habits = [];
  List<HabitLog> _logs = [];
  bool _isLoading = false;
  String? _error;

  // 今日进度缓存
  final Map<String, int> _todayProgress = {};

  // 提醒时间更新定时器
  Timer? _reminderUpdateTimer;

  // Getters
  List<Habit> get habits => _habits;
  List<Habit> get activeHabits => _habits.where((h) => h.isEnabled).toList();
  List<HabitLog> get logs => _logs;
  Map<String, int> get todayProgress => _todayProgress;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 初始化加载数据
  Future<void> loadData() async {
    debugPrint('===== HabitProvider.loadData 开始 =====');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _habitService.init();
      debugPrint('HabitService 初始化完成');

      // 加载习惯
      _habits = await _dbHelper.getAllHabits();
      debugPrint('从数据库加载到 ${_habits.length} 个习惯');

      // 如果没有习惯，插入默认习惯
      if (_habits.isEmpty) {
        final defaultHabits = PresetHabits.defaultHabits;
        for (var habit in defaultHabits) {
          try {
            await _dbHelper.insertHabit(habit);
            debugPrint('插入默认习惯: ${habit.title}');
          } catch (e) {
            debugPrint('插入默认习惯失败: ${habit.title}, 错误: $e');
          }
        }
        // 重新加载习惯列表
        _habits = await _dbHelper.getAllHabits();
        debugPrint('已插入 ${_habits.length} 个默认习惯');
      }

      // 加载今日日志
      await _loadTodayLogs();

      // 更新 HabitService 的习惯列表缓存
      _habitService.updateHabits(_habits);
      debugPrint('已更新 HabitService 的习惯列表缓存');

      // 启动提醒时间更新定时器（每30秒更新一次）
      _startReminderUpdateTimer();

      _isLoading = false;
      debugPrint('===== HabitProvider.loadData 完成 =====');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('===== HabitProvider.loadData 失败 =====');
      debugPrint('错误: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _error = e.toString();
      _isLoading = false;
      // 不抛出异常，避免影响其他模块加载
      notifyListeners();
    }
  }

  /// 加载今日日志
  Future<void> _loadTodayLogs() async {
    _logs = await _dbHelper.getTodayLogs();
    await _updateTodayProgress();
  }

  /// 更新今日进度
  Future<void> _updateTodayProgress() async {
    _todayProgress.clear();

    for (final habit in _habits) {
      if (habit.hasTarget && habit.needsRecord) {
        final count = await _dbHelper.getHabitTodayCount(habit.id);
        _todayProgress[habit.id] = count;
      }
    }
  }

  /// 记录完成
  Future<void> logCompletion(String habitId,
      {int? count, String status = 'completed'}) async {
    try {
      debugPrint('===== 记录习惯完成: $habitId =====');

      final habit = _habits.firstWhere((h) => h.id == habitId,
          orElse: () => throw Exception('习惯不存在: $habitId'));

      // 不需要记录的习惯
      if (!habit.needsRecord) {
        debugPrint('习惯不需要记录: ${habit.title}');
        return;
      }

      // 对于有目标的习惯，检查是否已经达到目标
      if (habit.hasTarget) {
        final currentCount = _todayProgress[habitId] ?? 0;
        debugPrint('当前进度: $currentCount/${habit.targetCount}');

        // 如果已经达到或超过目标，先清除今日记录，然后重新开始
        if (currentCount >= habit.targetCount) {
          debugPrint(
              '习惯 ${habit.title} 已达标($currentCount/${habit.targetCount})，清除记录后重新开始');
          await _dbHelper.clearHabitTodayLogs(habit.id);
          // 直接清空缓存，不需要重新加载
          _todayProgress[habitId] = 0;
        }
      }

      final log = HabitLog(
        id: const Uuid().v4(),
        habitId: habitId,
        count: count ?? 1,
        status: status == 'completed'
            ? HabitLogStatus.completed
            : HabitLogStatus.skipped,
        completedAt: DateTime.now(),
      );

      await _dbHelper.insertHabitLog(log);

      // 直接更新进度缓存，而不是重新加载所有日志
      if (habit.hasTarget) {
        final currentCount = _todayProgress[habitId] ?? 0;
        _todayProgress[habitId] = currentCount + 1;
        debugPrint('更新后进度: ${_todayProgress[habitId]}/${habit.targetCount}');
      }

      notifyListeners();
      _notifyNativeDataChanged('habit', habitId);
      debugPrint('习惯记录成功');
    } catch (e) {
      debugPrint('记录习惯失败: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 记录跳过
  Future<void> logSkipped(String habitId) async {
    await logCompletion(habitId, status: 'skipped');
  }

  /// 更新习惯
  Future<void> updateHabit(Habit habit) async {
    try {
      // 从数据库获取旧习惯
      Habit oldHabit = habit;
      try {
        final allHabits = await _dbHelper.getAllHabits();
        final foundHabit = allHabits.firstWhere(
          (h) => h.id == habit.id,
          orElse: () => habit,
        );
        oldHabit = foundHabit;
      } catch (e) {
        debugPrint('获取旧习惯失败: $e');
      }

      // 检查提醒相关字段是否改变
      final reminderFieldsChanged = oldHabit.isEnabled != habit.isEnabled ||
          oldHabit.triggerType != habit.triggerType ||
          oldHabit.intervalMinutes != habit.intervalMinutes ||
          oldHabit.fixedTime != habit.fixedTime ||
          oldHabit.scheduleType != habit.scheduleType ||
          oldHabit.referenceTime != habit.referenceTime;

      // 检查是否是上下班打卡时间变化
      final isClockTimeChanged =
          (habit.id == 'habit_clock_in' || habit.id == 'habit_clock_out') &&
              oldHabit.referenceTime != habit.referenceTime;

      debugPrint('===== updateHabit =====');
      debugPrint('习惯: ${habit.title}');
      debugPrint('提醒字段是否改变: $reminderFieldsChanged');
      debugPrint('打卡时间是否改变: $isClockTimeChanged');
      if (reminderFieldsChanged) {
        debugPrint('  - 启用状态: ${oldHabit.isEnabled} -> ${habit.isEnabled}');
        debugPrint('  - 触发类型: ${oldHabit.triggerType} -> ${habit.triggerType}');
        debugPrint(
            '  - 间隔分钟: ${oldHabit.intervalMinutes} -> ${habit.intervalMinutes}');
        debugPrint('  - 固定时间: ${oldHabit.fixedTime} -> ${habit.fixedTime}');
        debugPrint(
            '  - 参考时间: ${oldHabit.referenceTime} -> ${habit.referenceTime}');
      }

      await _dbHelper.updateHabit(habit);

      // 从数据库重新加载习惯列表，确保获取最新数据
      _habits = await _dbHelper.getAllHabits();
      debugPrint('从数据库重新加载习惯列表，习惯数: ${_habits.length}');

      // 更新 HabitService 的习惯列表缓存
      _habitService.updateHabits(_habits);

      // 如果提醒字段改变了，通知提醒服务重置状态
      if (reminderFieldsChanged && onReminderReset != null) {
        debugPrint('通知提醒服务重置习惯状态: ${habit.id}');
        onReminderReset!(habit.id);
      }

      // 如果是上下班打卡时间变化，通知喝水和起身活动更新提醒状态
      if (isClockTimeChanged && onReminderReset != null) {
        debugPrint('打卡时间变化，通知喝水和起身活动更新提醒状态');
        onReminderReset!('habit_water');
        onReminderReset!('habit_stretch');
      }

      await _loadTodayLogs();
      notifyListeners();
      _notifyNativeDataChanged('habit', habit.id);
    } catch (e) {
      debugPrint('更新习惯失败: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 启用/禁用习惯
  Future<void> toggleHabitEnabled(String id) async {
    final habit = _habits.firstWhere((h) => h.id == id);
    final updatedHabit = habit.copyWith(isEnabled: !habit.isEnabled);
    await updateHabit(updatedHabit);
  }

  /// 获取习惯的所有日志
  Future<List<HabitLog>> getHabitLogs(String habitId) async {
    return await _dbHelper.getHabitLogs(habitId);
  }

  /// 获取所有日志（按日期分组）
  Future<Map<String, List<HabitLog>>> getAllLogsByDate() async {
    return await _dbHelper.getAllLogsByDate();
  }

  /// 获取今日进度百分比
  int getTodayProgressPercentage(String habitId) {
    final habit = _habits.firstWhere((h) => h.id == habitId,
        orElse: () => throw Exception('习惯不存在: $habitId'));

    if (!habit.hasTarget) return 0;

    final completed = _todayProgress[habitId] ?? 0;
    return (completed * 100 ~/ habit.targetCount).clamp(0, 100);
  }

  /// 播报提醒语音
  Future<void> speakReminder(Habit habit, bool isZh) async {
    final voiceText = _habitService.getVoiceText(habit, isZh);
    if (habit.voiceEnabled) {
      await _habitService.speak(
        voiceText,
        voiceType: habit.voiceType,
        voiceStyle: habit.voiceStyle,
        speed: habit.voiceSpeed,
        customVoicePath: habit.customVoicePath,
      );
    }
  }

  /// 测试语音
  Future<void> testVoice(Habit habit, bool isZh) async {
    final voiceText = _habitService.getVoiceText(habit, isZh);
    await _habitService.testVoice(
      voiceText,
      voiceType: habit.voiceType,
      voiceStyle: habit.voiceStyle,
      speed: habit.voiceSpeed,
      customVoicePath: habit.customVoicePath,
    );
  }

  /// 启动提醒时间更新定时器
  void _startReminderUpdateTimer() {
    // 取消之前的定时器
    _reminderUpdateTimer?.cancel();

    // 每30秒更新一次提醒时间
    _reminderUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
  }

  /// 释放资源
  @override
  void dispose() {
    _reminderUpdateTimer?.cancel();
    _habitService.dispose();
    super.dispose();
  }
}
