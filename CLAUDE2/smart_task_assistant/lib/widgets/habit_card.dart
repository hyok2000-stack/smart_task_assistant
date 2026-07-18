import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../services/habit_service.dart';
import 'habit_streak_widget.dart';

/// 习惯卡片
class HabitCard extends StatelessWidget {
  static final HabitService _habitService = HabitService();

  final Habit habit;
  final VoidCallback? onRecord;
  final VoidCallback? onSettings;

  const HabitCard({
    super.key,
    required this.habit,
    this.onRecord,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    // 用 select 精确订阅本习惯的进度，避免任一习惯变化都重建本卡片
    final progress = context.select<HabitProvider, int>((p) => p.getTodayProgressPercentage(habit.id));
    final completed = context.select<HabitProvider, int>((p) => p.todayProgress[habit.id] ?? 0);
    // 获取本习惯今日打卡时间明细（completedAt 格式化）
    final todayCheckInTimes = context.select<HabitProvider, List<String>>(
      (p) => p.logs
          .where((log) => log.habitId == habit.id && log.isCompleted)
          .map((log) =>
              '${log.completedAt.hour.toString().padLeft(2, '0')}:${log.completedAt.minute.toString().padLeft(2, '0')}')
          .toList(),
    );

    // 计算下次提醒时间（启用的习惯）
    final nextReminderTime = habit.isEnabled
        ? _habitService.calculateNextTriggerTime(habit)
        : null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.02 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onSettings,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：图标和名称
              Row(
                children: [
                  // 图标
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _getHabitColor(habit.id),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        String.fromCharCode(habit.iconCode),
                        style: const TextStyle(fontSize: 24, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 名称和信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getHabitInfo(context, habit),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        // 下次提醒时间（仅间隔触发的习惯）
                        if (nextReminderTime != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatTime(nextReminderTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 提醒方式图标
                  Row(
                    children: [
                      if (habit.soundEnabled)
                        Icon(Icons.notifications, size: 16, color: Colors.grey[400]),
                      if (habit.vibrationEnabled)
                        Icon(Icons.vibration_outlined, size: 16, color: Colors.grey[400]),
                      if (habit.voiceEnabled)
                        Icon(Icons.volume_up, size: 16, color: Colors.grey[400]),
                    ],
                  ),
                  // 进入提示：整行已可点击进入设置/详情，这里仅作视觉引导，
                  // 不再单独包 InkWell（避免与整行点击形成两个重复入口）
                  Icon(Icons.chevron_right, size: 22, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 12),
              // 进度条
              if (habit.hasTarget) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress / 100.0,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getHabitColor(habit.id),
                        ),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$completed/${habit.targetCount}${habit.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                // 今日打卡时间明细
                if (todayCheckInTimes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        Icon(Icons.schedule, size: 12, color: Colors.grey[400]),
                        ...todayCheckInTimes.map((time) => Text(
                              '$time',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            )).expand((w) => [w, const Text(' · ', style: TextStyle(fontSize: 11, color: Colors.grey))]).toList()
                              ..removeLast(),
                      ],
                    ),
                  ),
                // 连续打卡天数 + 近 7 天热力
                HabitStreakWidget(
                  habit: habit,
                  color: _getHabitColor(habit.id),
                ),
                const SizedBox(height: 12),
                // 操作按钮——达标时变为「✓ 今日已完成」并改色
                Builder(builder: (context) {
                  final isCompleted = habit.hasTarget && completed >= habit.targetCount;
                  return Row(
                    children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ElevatedButton.icon(
                            onPressed: onRecord,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCompleted
                                  ? Colors.green
                                  : _getHabitColor(habit.id),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: Icon(
                              isCompleted ? Icons.check_circle : Icons.add_circle_outline,
                              size: 18,
                            ),
                            label: Text(
                              isCompleted
                                  ? '今日已完成'
                                  : (habit.hasTarget ? '+ 记录' : '知道了'),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 获取习惯颜色
  Color _getHabitColor(String habitId) {
    switch (habitId) {
      case 'habit_water':
        return const Color(0xFF3B82F6); // 蓝色
      case 'habit_stretch':
        return const Color(0xFF10B981); // 绿色
      case 'habit_clock_in':
        return const Color(0xFFF59E0B); // 橙色
      case 'habit_clock_out':
        return const Color(0xFFEF4444); // 红色
      default:
        return const Color(0xFF6366f1); // 默认紫色
    }
  }

  /// 格式化时间显示
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);

    // 如果是过去时间
    if (diff.isNegative) {
      return '刚刚';
    }

    // 计算天数差异
    final today = DateTime(now.year, now.month, now.day);
    final timeDate = DateTime(time.year, time.month, time.day);
    final diffDays = timeDate.difference(today).inDays;

    // 如果是今天，显示相对时间
    if (diffDays == 0) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;

      if (hours > 0) {
        final minText = minutes > 0 ? '$minutes分钟' : '';
        return '下次: $hours小时$minText后';
      } else if (minutes > 0) {
        return '下次: $minutes分钟后';
      } else if (diff.inSeconds < 60) {
        return '下次: 即将提醒';
      }
    }

    // 如果是明天或更远，显示具体时间
    if (diffDays == 1) {
      return '下次: 明天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diffDays > 1 && diffDays <= 7) {
      final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final weekday = time.weekday;
      return '下次: ${weekdays[weekday]} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '下次: ${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  /// 获取习惯信息
  String _getHabitInfo(BuildContext context, Habit habit) {
    final scheduleType = habit.scheduleType == 'weekdays'
        ? '工作日'
        : '每天';

    if (habit.triggerType == 'interval') {
      final interval = habit.intervalMinutes ?? 60;
      if (interval < 60) {
        return '$scheduleType | 每$interval分钟';
      } else {
        final hours = interval ~/ 60;
        final minutes = interval % 60;
        if (minutes > 0) {
          return '$scheduleType | 每$hours小时$minutes分钟';
        } else {
          return '$scheduleType | 每$hours小时';
        }
      }
    } else {
      // 固定时间
      final time = habit.fixedTime ?? '';
      if (habit.id == 'habit_clock_in' && habit.referenceTime != null && habit.referenceTime != '09:00') {
        return '$scheduleType | $time (上班时间: ${habit.referenceTime})';
      } else if (habit.id == 'habit_clock_out' && habit.referenceTime != null && habit.referenceTime != '18:00') {
        return '$scheduleType | $time (下班时间: ${habit.referenceTime})';
      } else {
        return '$scheduleType | $time';
      }
    }
  }
}