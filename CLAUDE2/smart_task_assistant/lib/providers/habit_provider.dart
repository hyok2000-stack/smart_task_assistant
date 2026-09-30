import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../database/database_helper.dart';
import '../services/habit_service.dart';

/// 习惯记录结果
///
/// [logCompletion] 在不同状态下返回不同结果，便于 UI 层决定是否需要
/// 弹出确认框（避免用户在已达标时误点导致当日进度被清空）。
enum HabitLogResult {
  /// 正常记录成功（未达标）
  recorded,

  /// 已达到今日目标，UI 可提示用户已完成
  targetReached,

  /// 当日记录已重置（仅在 [resetTodayProgress] 被显式调用后才会出现）
  reset,
}

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
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // invokeMethod 返回 Future，真正的 PlatformException 是异步到达的，
    // 同步 try/catch 无法捕获——必须用 catchError。
    _reminderChannel
        .invokeMethod('notifyDataChanged', {'type': type, 'id': id})
        .catchError((_) {});
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

  /// 更新今日进度（使用批量查询）
  Future<void> _updateTodayProgress() async {
    _todayProgress.clear();

    final habitIds = _habits
        .where((h) => h.hasTarget && h.needsRecord)
        .map((h) => h.id)
        .toList();

    if (habitIds.isEmpty) return;

    final counts = await _dbHelper.getHabitTodayCountsBatch(habitIds);
    _todayProgress.addAll(counts);
  }

  /// 记录完成
  ///
  /// 返回 [HabitLogResult]：
  /// - [HabitLogResult.recorded]：正常记录成功；
  /// - [HabitLogResult.targetReached]：已达今日目标，未追加记录，UI 可提示"今日已完成"，
  ///   如需重置需显式调用 [resetTodayProgress]（避免误点清空当日进度）。
  Future<HabitLogResult> logCompletion(String habitId,
      {int? count, String status = 'completed'}) async {
    try {
      debugPrint('===== 记录习惯完成: $habitId =====');

      final habit = _habits.firstWhere((h) => h.id == habitId,
          orElse: () => throw Exception('习惯不存在: $habitId'));

      // 不需要记录的习惯
      if (!habit.needsRecord) {
        debugPrint('习惯不需要记录: ${habit.title}');
        return HabitLogResult.recorded;
      }

      // 对于有目标的习惯：已达标时不再自动清空，提示用户已完成。
      // 重置必须显式调用 [resetTodayProgress]，避免误点导致一天白干。
      if (habit.hasTarget) {
        final currentCount = _todayProgress[habitId] ?? 0;
        debugPrint('当前进度: $currentCount/${habit.targetCount}');

        if (currentCount >= habit.targetCount) {
          debugPrint(
              '习惯 ${habit.title} 已达标($currentCount/${habit.targetCount})，不再追加记录');
          return HabitLogResult.targetReached;
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
      return HabitLogResult.recorded;
    } catch (e) {
      debugPrint('记录习惯失败: $e');
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 显式重置某习惯的今日进度（清空当日记录重新开始）。
  ///
  /// 应在 UI 层经过二次确认后调用。替代旧版 [logCompletion] 中
  /// "达标后自动清空" 的隐性行为，避免误操作丢失数据。
  Future<void> resetTodayProgress(String habitId) async {
    try {
      final habit = _habits.firstWhere((h) => h.id == habitId,
          orElse: () => throw Exception('习惯不存在: $habitId'));
      if (!habit.hasTarget) return;

      debugPrint('===== 重置习惯今日进度: $habitId =====');
      await _dbHelper.clearHabitTodayLogs(habitId);
      _todayProgress[habitId] = 0;
      notifyListeners();
      _notifyNativeDataChanged('habit', habitId);
    } catch (e) {
      debugPrint('重置习惯今日进度失败: $e');
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 记录跳过
  Future<void> logSkipped(String habitId) async {
    await logCompletion(habitId, status: 'skipped');
  }

  /// 更新习惯
  Future<void> updateHabit(Habit habit) async {
    try {
      // 从内存列表获取旧习惯（避免全表数据库查询）
      final habitIndex = _habits.indexWhere((h) => h.id == habit.id);
      Habit oldHabit = habitIndex >= 0 ? _habits[habitIndex] : habit;

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

      // 内存中直接替换，避免全表 reload
      if (habitIndex >= 0) {
        _habits[habitIndex] = habit;
      }

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
    final index = _habits.indexWhere((h) => h.id == id);
    if (index < 0) {
      debugPrint('toggleHabitEnabled: 习惯不存在 $id');
      return;
    }
    final habit = _habits[index];
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

  /// 获取习惯近 [days] 天的每日完成量（升序），用于 streak 计算与热力图展示。
  Future<List<({DateTime date, int count})>> getRecentDailyCounts(
      String habitId,
      {int days = 30}) async {
    return _dbHelper.getHabitDailyCounts(habitId, days: days);
  }

  /// 计算习惯的连续达标天数（streak）。
  ///
  /// 规则：从今天起向前数，当天完成量 ≥ [Habit.targetCount] 即视为达标。
  /// 今天尚未达标不中断 streak（只统计到昨天为止的连续达标天数），
  /// 这样用户不会因为"今天还没完成"而看到 streak 归零。
  Future<int> calculateStreak(String habitId) async {
    try {
      final habit = _habits.firstWhere((h) => h.id == habitId,
          orElse: () => throw Exception('习惯不存在: $habitId'));
      if (!habit.hasTarget) return 0;

      final daily = await _dbHelper.getHabitDailyCounts(habitId, days: 365);
      if (daily.isEmpty) return 0;

      final target = habit.targetCount;
      // 按日期降序（最新在前）
      final desc = daily.reversed.toList();
      // 今天是否达标：达标则计入 streak，否则从昨天开始数
      int i = 0;
      if (desc.first.count < target) {
        // 今天没达标，跳过今天，从昨天算起
        i = 1;
      }
      int streak = 0;
      for (; i < desc.length; i++) {
        if (desc[i].count >= target) {
          streak++;
        } else {
          break;
        }
      }
      return streak;
    } catch (e) {
      debugPrint('计算 streak 失败: $e');
      return 0;
    }
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

  /// 启动提醒时间更新定时器（已优化：移除无条件 notifyListeners Timer）
  void _startReminderUpdateTimer() {
    // 无条件定时器已移除，仅在数据变更时通知
  }

  /// 释放资源
  @override
  void dispose() {
    _reminderUpdateTimer?.cancel();
    _habitService.dispose();
    super.dispose();
  }
}
