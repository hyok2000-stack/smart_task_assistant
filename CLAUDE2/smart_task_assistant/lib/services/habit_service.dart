import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/habit.dart';
import 'tts_service.dart';

/// 习惯服务 - 业务逻辑层
class HabitService {
  static final HabitService _instance = HabitService._internal();
  factory HabitService() => _instance;
  HabitService._internal();

  // 使用共享的 TTSService 单例
  final TTSService _ttsService = TTSService();

  // 习惯列表缓存（用于获取打卡时间）
  List<Habit>? _cachedHabits;

  /// 更新习惯列表缓存
  void updateHabits(List<Habit> habits) {
    _cachedHabits = habits;
  }

  /// 获取工作时间范围（从打卡习惯获取）
  /// 返回 (上班时间, 下班时间)，如果无法获取则使用默认值 (09:00, 18:00)
  (DateTime, DateTime) _getWorkTimeRange(DateTime now) {
    debugPrint('===== _getWorkTimeRange =====');
    debugPrint('  - 当前时间: ${now.toIso8601String()}');
    debugPrint('  - 习惯列表缓存: ${_cachedHabits != null ? "已缓存 (${_cachedHabits!.length} 个习惯)" : "未缓存"}');

    // 默认工作时间
    const defaultStartTime = 9; // 9:00
    const defaultEndTime = 18; // 18:00

    if (_cachedHabits == null) {
      debugPrint('    → 习惯列表未缓存，使用默认工作时间: $defaultStartTime:00 - $defaultEndTime:00');
      return (
        DateTime(now.year, now.month, now.day, defaultStartTime, 0),
        DateTime(now.year, now.month, now.day, defaultEndTime, 0),
      );
    }

    // 查找上班打卡和下班打卡习惯
    Habit? clockInHabit;
    Habit? clockOutHabit;

    debugPrint('  - 查找打卡习惯:');
    for (final habit in _cachedHabits!) {
      if (habit.id == 'habit_clock_in') {
        debugPrint('    - habit_clock_in: isEnabled=${habit.isEnabled}, referenceTime=${habit.referenceTime}');
        if (habit.isEnabled && habit.referenceTime != null) {
          clockInHabit = habit;
        }
      } else if (habit.id == 'habit_clock_out') {
        debugPrint('    - habit_clock_out: isEnabled=${habit.isEnabled}, referenceTime=${habit.referenceTime}');
        if (habit.isEnabled && habit.referenceTime != null) {
          clockOutHabit = habit;
        }
      }
    }

    int startHour = defaultStartTime;
    int endHour = defaultEndTime;

    // 解析上班时间
    if (clockInHabit != null && clockInHabit.referenceTime != null) {
      final parts = clockInHabit.referenceTime!.split(':');
      if (parts.isNotEmpty) startHour = int.tryParse(parts[0]) ?? defaultStartTime;
      debugPrint('    → 使用上班打卡时间: ${clockInHabit.referenceTime}');
    } else {
      debugPrint('    → 上班打卡未启用或未设置，使用默认时间: $defaultStartTime:00');
    }

    // 解析下班时间
    if (clockOutHabit != null) {
      final parts = clockOutHabit.referenceTime!.split(':');
      endHour = int.tryParse(parts[0]) ?? defaultEndTime;
      debugPrint('    → 使用下班打卡时间: ${clockOutHabit.referenceTime}');
    } else {
      debugPrint('    → 下班打卡未启用或未设置，使用默认时间: $defaultEndTime:00');
    }

    final result = (
      DateTime(now.year, now.month, now.day, startHour, 0),
      DateTime(now.year, now.month, now.day, endHour, 0),
    );
    debugPrint('    → 返回工作时间范围: ${result.$1.toIso8601String()} - ${result.$2.toIso8601String()}');
    return result;
  }

  /// 播放语音并等待完成
  Future<void> speakAndWait({
    required String text,
    String? speed,
    String? voiceType,
    String? voiceStyle,
    String? customVoicePath,
  }) async {
    await _ttsService.speakAndWait(
      text: text,
      voiceType: voiceType,
      voiceStyle: voiceStyle,
      speed: speed,
      customVoicePath: customVoicePath,
    );
  }

  /// 初始化（委托给 TTSService）
  Future<void> init() async {
    await _ttsService.init();
  }

  /// 销毁资源（委托给 TTSService）
  Future<void> dispose() async {
    await _ttsService.stopSpeaking();
  }

  // ==================== 时间计算 ====================

  /// 计算下次触发时间
  DateTime? calculateNextTriggerTime(Habit habit) {
    debugPrint('===== calculateNextTriggerTime: ${habit.title} =====');
    debugPrint('  - ID: ${habit.id}');
    debugPrint('  - triggerType: ${habit.triggerType}');
    debugPrint('  - intervalMinutes: ${habit.intervalMinutes}');
    debugPrint('  - fixedTime: ${habit.fixedTime}');
    debugPrint('  - referenceTime: ${habit.referenceTime}');

    final now = DateTime.now();

    if (habit.triggerType == 'fixed') {
      // 固定时间触发
      return _calculateNextFixedTime(habit, now);
    } else {
      // 时间间隔触发
      return _calculateNextIntervalTime(habit, now);
    }
  }

  /// 计算固定时间的下次触发
  DateTime? _calculateNextFixedTime(Habit habit, DateTime now) {
    // 检查是否是打卡习惯
    final isClockHabit = habit.id == 'habit_clock_in' || habit.id == 'habit_clock_out';

    String timeString;
    if (isClockHabit) {
      // 打卡习惯使用参考时间
      if (habit.referenceTime == null) return null;
      timeString = habit.referenceTime!;
    } else {
      // 非打卡习惯使用固定时间
      if (habit.fixedTime == null) return null;
      timeString = habit.fixedTime!;
    }

    // 解析时间 HH:mm
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    // 创建今天的触发时间
    DateTime triggerTime = DateTime(now.year, now.month, now.day, hour, minute);

    // 上班打卡：根据提前提醒分钟数计算提醒时间
    if (habit.id == 'habit_clock_in' && habit.advanceMinutes != null) {
      triggerTime = triggerTime.subtract(Duration(minutes: habit.advanceMinutes!));
      debugPrint('    上班打卡提醒时间: ${triggerTime.toIso8601String()} (提前${habit.advanceMinutes}分钟)');
    }

    // 如果今天的时间已过，设置为明天
    if (now.isAfter(triggerTime)) {
      triggerTime = triggerTime.add(const Duration(days: 1));
    }

    // 检查是否是工作日
    if (habit.scheduleType == 'weekdays' && !_isWeekday(triggerTime)) {
      // 找到下一个工作日
      while (!_isWeekday(triggerTime)) {
        triggerTime = triggerTime.add(const Duration(days: 1));
      }
    }

    return triggerTime;
  }

  /// 计算时间间隔的下次触发
  DateTime? _calculateNextIntervalTime(Habit habit, DateTime now) {
    debugPrint('===== _calculateNextIntervalTime =====');
    debugPrint('  - habit: ${habit.title} (${habit.id})');
    debugPrint('  - intervalMinutes: ${habit.intervalMinutes}');
    debugPrint('  - now: ${now.toIso8601String()}');

    if (habit.intervalMinutes == null || habit.intervalMinutes! <= 0) {
      debugPrint('  → 间隔分钟为空或<=0，返回 null');
      return null;
    }

    // 判断是否是喝水或起身活动习惯
    final isWorkHabit = habit.id == 'habit_water' || habit.id == 'habit_stretch';

    DateTime startTime;
    DateTime endTime;
    int interval = habit.intervalMinutes!;

    if (isWorkHabit) {
      // 使用工作时间范围
      final workRange = _getWorkTimeRange(now);
      startTime = workRange.$1;
      endTime = workRange.$2;
      debugPrint('    计算下次触发时间（工作习惯模式），工作时间: ${startTime.hour}:00 - ${endTime.hour}:00');
    } else {
      // 非工作习惯，使用原来的逻辑
      startTime = DateTime(now.year, now.month, now.day, 9, 0);
      endTime = startTime.add(const Duration(hours: 9));
      debugPrint('    计算下次触发时间（非工作习惯模式），默认时间: 9:00 - 18:00');
    }

    // 如果当前时间已过结束时间，从明天开始
    if (now.isAfter(endTime)) {
      startTime = startTime.add(const Duration(days: 1));
      endTime = endTime.add(const Duration(days: 1));
    }

    // 计算下一个触发时间
    DateTime nextTriggerTime = startTime;

    // 添加循环保护，最多计算 1000 次迭代
    int iterations = 0;
    const maxIterations = 1000;

    while ((nextTriggerTime.isBefore(now) || nextTriggerTime.isAfter(endTime)) && iterations < maxIterations) {
      nextTriggerTime = nextTriggerTime.add(Duration(minutes: interval));
      // 如果超过结束时间，跳到下一天的开始时间
      if (nextTriggerTime.isAfter(endTime)) {
        startTime = startTime.add(const Duration(days: 1));
        endTime = endTime.add(const Duration(days: 1));
        nextTriggerTime = startTime;
      }
      iterations++;
    }

    if (iterations >= maxIterations) {
      debugPrint('    计算下次触发时间失败：达到最大迭代次数');
      return null;
    }

    // 检查是否是工作日
    if (habit.scheduleType == 'weekdays' && !_isWeekday(nextTriggerTime)) {
      // 如果不是工作日，跳到下一个工作日的上班时间
      int weekdayIterations = 0;
      while (!_isWeekday(nextTriggerTime) && weekdayIterations < 7) {
        nextTriggerTime = nextTriggerTime.add(const Duration(days: 1));
        weekdayIterations++;
      }
      // 使用工作时间的开始时间
      final workRange = _getWorkTimeRange(nextTriggerTime);
      nextTriggerTime = workRange.$1;
    }

    debugPrint('    计算结果下次触发时间: ${nextTriggerTime.toIso8601String()}');
    return nextTriggerTime;
  }

  /// 检查是否应该触发提醒
  bool shouldTriggerReminder(Habit habit, DateTime now) {
    debugPrint('===== shouldTriggerReminder 检查: ${habit.title} =====');
    debugPrint('  - 启用状态: ${habit.isEnabled}');
    debugPrint('  - 调度类型: ${habit.scheduleType}');
    debugPrint('  - 触发类型: ${habit.triggerType}');
    debugPrint('  - 当前时间: ${now.toIso8601String()}');

    // 检查是否启用
    if (!habit.isEnabled) {
      debugPrint('  → 未启用，跳过');
      return false;
    }

    // 检查是否是工作日
    final isWeekday = _isWeekday(now);
    debugPrint('  - 是否工作日: $isWeekday (${now.weekday})');
    if (habit.scheduleType == 'weekdays' && !isWeekday) {
      debugPrint('  → 不是工作日，跳过');
      return false;
    }

    // 检查触发时间
    if (habit.triggerType == 'fixed') {
      return _shouldTriggerFixedTime(habit, now);
    } else {
      return _shouldTriggerInterval(habit, now);
    }
  }

  /// 检查固定时间触发
  bool _shouldTriggerFixedTime(Habit habit, DateTime now) {
    // 检查是否是打卡习惯
    final isClockHabit = habit.id == 'habit_clock_in' || habit.id == 'habit_clock_out';

    String timeString;
    if (isClockHabit) {
      // 打卡习惯使用参考时间
      if (habit.referenceTime == null) return false;
      timeString = habit.referenceTime!;
    } else {
      // 非打卡习惯使用固定时间
      if (habit.fixedTime == null) return false;
      timeString = habit.fixedTime!;
    }

    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    DateTime triggerTime = DateTime(now.year, now.month, now.day, hour, minute);

    // 上班打卡：根据提前提醒分钟数计算提醒时间
    if (habit.id == 'habit_clock_in' && habit.advanceMinutes != null) {
      triggerTime = triggerTime.subtract(Duration(minutes: habit.advanceMinutes!));
    }

    // 检查是否在触发时间后的1分钟内
    final diff = now.difference(triggerTime);

    debugPrint('  - 固定时间: ${habit.fixedTime}');
    debugPrint('  - 触发时间: ${triggerTime.toIso8601String()}');
    debugPrint('  - 时间差: ${diff.inSeconds}秒');

    final shouldTrigger = diff.inSeconds >= 0 && diff.inMinutes < 1;
    debugPrint('  → 触发结果: $shouldTrigger');

    return shouldTrigger;
  }

  /// 检查间隔时间触发
  bool _shouldTriggerInterval(Habit habit, DateTime now) {
    debugPrint('  ===== _shouldTriggerInterval 检查 =====');
    debugPrint('    - 习惯: ${habit.title}');
    debugPrint('    - 间隔分钟: ${habit.intervalMinutes}');
    debugPrint('    - 当前时间: ${now.toIso8601String()}');

    if (habit.intervalMinutes == null) {
      debugPrint('    → 间隔分钟为空，返回 false');
      return false;
    }

    // 获取今天的触发时间列表
    final triggerTimes = _getTodayIntervalTriggers(habit);
    debugPrint('    - 触发时间列表 (${triggerTimes.length}个):');

    // 找到最近的一个触发时间（在未来或刚刚过去）
    DateTime? closestTrigger;
    int? closestDiffSeconds;

    for (int i = 0; i < triggerTimes.length; i++) {
      final triggerTime = triggerTimes[i];
      final diff = now.difference(triggerTime);
      debugPrint('      [$i] ${triggerTime.toIso8601String()} (差值: ${diff.inSeconds}秒)');

      // 找到最小的绝对时间差
      final absDiff = diff.abs().inSeconds;
      if (closestDiffSeconds == null || absDiff < closestDiffSeconds) {
        closestDiffSeconds = absDiff;
        closestTrigger = triggerTime;
      }

      // 检查是否在触发时间后的1分钟内
      if (diff.inSeconds >= 0 && diff.inMinutes < 1) {
        debugPrint('    → 匹配触发时间！');
        return true;
      }
    }

    debugPrint('    → 未匹配任何触发时间');
    debugPrint('    → 最近触发时间: $closestTrigger (差值: $closestDiffSeconds秒)');
    return false;
  }

  /// 获取今天的间隔触发时间列表
  List<DateTime> _getTodayIntervalTriggers(Habit habit) {
    final now = DateTime.now();
    final intervalMinutes = habit.intervalMinutes ?? 60;

    // 判断是否是喝水或起身活动习惯
    final isWorkHabit = habit.id == 'habit_water' || habit.id == 'habit_stretch';

    DateTime startTime;
    DateTime endTime;

    if (isWorkHabit) {
      // 使用工作时间范围
      final workRange = _getWorkTimeRange(now);
      startTime = workRange.$1;
      endTime = workRange.$2;
      debugPrint('    工作习惯模式（喝水/起身活动），工作时间: ${startTime.hour}:00 - ${endTime.hour}:00');
    } else {
      // 非工作习惯，使用原来的逻辑
      if (intervalMinutes <= 30) {
        // 短间隔：从当前时间往前推
        startTime = now.subtract(Duration(minutes: intervalMinutes * 3));
        endTime = now.add(const Duration(minutes: 10));
        debugPrint('    短间隔模式，触发时间范围: $startTime - $endTime');
      } else {
        // 长间隔：默认从9点开始
        startTime = DateTime(now.year, now.month, now.day, 9, 0);
        endTime = now.add(const Duration(hours: 1));
        debugPrint('    长间隔模式，触发时间范围: $startTime - $endTime');
      }
    }

    List<DateTime> triggers = [];
    DateTime current = startTime;

    // 从开始时间按间隔生成触发时间，直到结束时间
    while (current.isBefore(endTime) || current.isAtSameMomentAs(endTime)) {
      triggers.add(current);
      current = current.add(Duration(minutes: intervalMinutes));
    }

    debugPrint('    生成的触发时间列表 (${triggers.length}个):');
    for (int i = 0; i < triggers.length; i++) {
      final diff = now.difference(triggers[i]);
      debugPrint('      [$i] ${triggers[i].toIso8601String()} (差值: ${diff.inSeconds}秒)');
    }

    return triggers;
  }

  /// 判断是否是工作日（周一到周五）
  bool _isWeekday(DateTime date) {
    // DateTime.weekday 返回：1=周一, 7=周日
    return date.weekday >= 1 && date.weekday <= 5;
  }

  // ==================== 语音播报 ====================

  /// 播报语音（委托给共享 TTSService）
  Future<void> speak(
    String text, {
    String? speed,
    String? voiceType,
    String? voiceStyle,
    String? customVoicePath,
  }) async {
    debugPrint('===== HabitService.speak 委托给 TTSService =====');
    await _ttsService.speak(
      text: text,
      voiceType: voiceType,
      voiceStyle: voiceStyle,
      speed: speed,
      customVoicePath: customVoicePath,
    );
  }

  /// 播放自定义语音文件（委托给 TTSService）
  Future<void> playCustomVoice(String path) async {
    await _ttsService.playCustomVoice(path);
  }

  /// 停止语音播报（委托给 TTSService）
  Future<void> stopSpeaking() async {
    await _ttsService.stopSpeaking();
  }

  /// 根据习惯类型获取语音内容
  String getVoiceText(Habit habit, bool isZh) {
    if (habit.voiceText != null && habit.voiceText!.isNotEmpty) {
      return habit.voiceText!;
    }

    // 默认语音内容
    final Map<String, String> zhVoices = {
      'habit_water': '该休息一下了，喝水',
      'habit_stretch': '时间到了，起身活动一下',
      'habit_clock_in': '该打卡了',
      'habit_clock_out': '下班时间到了',
    };

    final Map<String, String> enVoices = {
      'habit_water': 'Time for a break, drink water',
      'habit_stretch': 'Time to stretch',
      'habit_clock_in': 'Time to clock in',
      'habit_clock_out': 'Time to clock out',
    };

    final voices = isZh ? zhVoices : enVoices;
    return voices[habit.id] ?? habit.title;
  }

  /// 测试语音
  Future<void> testVoice(
    String text, {
    String? speed,
    String? voiceType,
    String? voiceStyle,
    String? customVoicePath,
  }) async {
    await speakAndWait(
      text: text,
      speed: speed,
      voiceType: voiceType,
      voiceStyle: voiceStyle,
      customVoicePath: customVoicePath,
    );
  }
}