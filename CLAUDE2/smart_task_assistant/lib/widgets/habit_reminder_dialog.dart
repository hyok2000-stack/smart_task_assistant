import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../services/reminder_service.dart';

/// 习惯提醒对话框
class HabitReminderDialog extends StatelessWidget {
  final Habit habit;

  const HabitReminderDialog({
    super.key,
    required this.habit,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final progress = provider.getTodayProgressPercentage(habit.id);
    final completed = provider.todayProgress[habit.id] ?? 0;
    final isClockHabit = habit.id == 'habit_clock_in' ||
        habit.id == 'habit_clock_out';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标和标题
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _getHabitColor(habit.id),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(habit.iconCode),
                  style: const TextStyle(fontSize: 32, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              habit.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _getReminderText(habit),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            // 进度显示（非打卡习惯）
            if (!isClockHabit) ...[
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日目标: ${habit.targetCount}${habit.unit}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    '已完成: $completed${habit.unit}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress / 100.0,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getHabitColor(habit.id),
                ),
                borderRadius: BorderRadius.circular(4),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Text(
                '$progress%',
                style: TextStyle(
                  color: _getHabitColor(habit.id),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 提醒方式图标
            Wrap(
              spacing: 8,
              children: [
                if (habit.soundEnabled)
                  _buildReminderChip(Icons.notifications, '声音'),
                if (habit.vibrationEnabled)
                  _buildReminderChip(Icons.vibration_outlined, '振动'),
                if (habit.voiceEnabled)
                  _buildReminderChip(Icons.volume_up, '语音'),
              ],
            ),
            const SizedBox(height: 24),
            // 操作按钮
            if (isClockHabit) ...[
              // 打卡提醒 - 只有关闭按钮
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _getHabitColor(habit.id),
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('知道了'),
              ),
            ] else ...[
              // 需要记录的习惯 - 完成和跳过按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        // 今天不再提醒：snooze 到今天 24:00，明天自动恢复
                        final now = DateTime.now();
                        final tomorrow = DateTime(now.year, now.month, now.day + 1);
                        final minutesUntilTomorrow =
                            tomorrow.difference(now).inMinutes + 1;
                        ReminderService()
                            .snoozeHabit(habit.id, minutesUntilTomorrow);
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _getHabitColor(habit.id)),
                        minimumSize: const Size(0, 48),
                      ),
                      child: Text(
                        '不再提醒',
                        style: TextStyle(color: _getHabitColor(habit.id)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final result = await provider.logCompletion(habit.id);
                        if (!context.mounted) return;
                        // 已达标时提示，不静默吞掉
                        if (result == HabitLogResult.targetReached) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${habit.title} 今日目标已完成 ✓'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _getHabitColor(habit.id),
                        minimumSize: const Size(0, 48),
                      ),
                      child: const Text('已完成'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 稍后提醒选项
              Wrap(
                spacing: 8,
                children: [
                  _buildSnoozeButton(context, habit, 5, '5分钟'),
                  _buildSnoozeButton(context, habit, 15, '15分钟'),
                  _buildSnoozeButton(context, habit, 30, '30分钟'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 获取提醒文本
  String _getReminderText(Habit habit) {
    if (habit.voiceText != null && habit.voiceText!.isNotEmpty) {
      return habit.voiceText!;
    }

    switch (habit.id) {
      case 'habit_water':
        return '该休息一下了！';
      case 'habit_stretch':
        return '时间到了，起身活动一下！';
      case 'habit_clock_in':
        return '该打卡了！';
      case 'habit_clock_out':
        return '下班时间到了！';
      default:
        return '该执行这个习惯了！';
    }
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

  /// 构建提醒方式芯片
  Widget _buildReminderChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建稍后提醒按钮
  Widget _buildSnoozeButton(BuildContext context, Habit habit, int minutes, String label) {
    return OutlinedButton(
      onPressed: () {
        // 真正实现稍后提醒：记录 snooze 时间，期间不再重复触发
        ReminderService().snoozeHabit(habit.id, minutes);
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('将在 $minutes 分钟后再次提醒'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(label),
    );
  }
}