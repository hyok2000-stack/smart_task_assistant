import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';

/// 习惯连续打卡 + 近 7 天完成情况展示。
///
/// 数据来源：
/// - 连续天数（streak）和历史天数：[HabitProvider.getRecentDailyCounts]（异步查 DB）
/// - 今日进度：直接从 [HabitProvider.todayProgress] 读取（内存，实时更新）
///
/// 点击「+ 记录」后今日圆点会立即更新（通过 select 监听进度变化）。
class HabitStreakWidget extends StatefulWidget {
  final Habit habit;
  final Color color;

  const HabitStreakWidget({
    super.key,
    required this.habit,
    required this.color,
  });

  @override
  State<HabitStreakWidget> createState() => _HabitStreakWidgetState();
}

class _HabitStreakWidgetState extends State<HabitStreakWidget> {
  int _streak = 0;
  List<({DateTime date, int count})> _recent = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final provider = context.read<HabitProvider>();
    final streak = await provider.calculateStreak(widget.habit.id);
    final recent = await provider.getRecentDailyCounts(widget.habit.id, days: 7);
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _recent = recent;
      _loading = false;
    });
  }

  /// 重新加载（进度变化时调用）
  void _refresh() {
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.habit.hasTarget) return const SizedBox.shrink();

    final target = widget.habit.targetCount;

    // 监听今日进度变化——点击「+ 记录」后这里会触发 rebuild
    final todayCount = context.select<HabitProvider, int>(
      (p) => p.todayProgress[widget.habit.id] ?? 0,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签行：连续天数 + 近 7 天说明
          Row(
            children: [
              _buildStreakBadge(),
              const Spacer(),
              Text(
                '近 7 天',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 近 7 天圆点
          _buildWeeklyHeatmap(target, todayCount),
        ],
      ),
    );
  }

  /// 连续打卡天数徽章
  Widget _buildStreakBadge() {
    if (_loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // streak 为 0 时显示鼓励文案，而非冰冷的"连续 0 天"
    final streakText = _streak > 0
        ? '🔥 连续 $_streak 天'
        : '🎯 今日开始打卡';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: _streak > 0 ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        streakText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _streak > 0 ? widget.color : Colors.grey[500],
        ),
      ),
    );
  }

  /// 近 7 天完成情况（圆点：达标填充色 / 未达标灰色）
  ///
  /// [todayCount] 是实时从 Provider 内存读取的今日进度，
  /// 覆盖 _recent 中最后一天（今天）的缓存值，确保点击后立即更新。
  Widget _buildWeeklyHeatmap(int target, int todayCount) {
    if (_loading || _recent.isEmpty) {
      return const SizedBox(
        height: 24,
        child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 均匀分布 7 个圆点，每个带星期标签
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_recent.length, (i) {
        final d = _recent[i];
        // 今天用实时 todayCount 覆盖 DB 缓存值
        final count = (d.date.day == today.day &&
                d.date.month == today.month &&
                d.date.year == today.year)
            ? todayCount
            : d.count;
        final reached = count >= target;
        final isToday = d.date.day == today.day &&
            d.date.month == today.month &&
            d.date.year == today.year;
        // 部分进度比例（0~1），让打卡有可见反馈
        final progress = target > 0 ? (count / target).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: '${d.date.month}/${d.date.day}: $count/$target',
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 达标：实色；有部分进度：半透明实色（随进度加深）；
                // 无进度：极淡背景色
                color: reached
                    ? widget.color
                    : (count > 0
                        ? widget.color.withValues(alpha: 0.15 + progress * 0.55)
                        : widget.color.withValues(alpha: 0.1)),
                border: isToday
                    ? Border.all(color: widget.color, width: 1.5)
                    : null,
              ),
              // 有进度但未达标时，中心显示数字（更直观）
              child: count > 0 && !reached
                  ? Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: widget.color,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
