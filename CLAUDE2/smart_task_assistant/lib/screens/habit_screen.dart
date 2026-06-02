import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_settings_dialog.dart';

/// 习惯标签页 - 统一互联网风格
class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final provider = context.read<HabitProvider>();
    await provider.loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Container(
      color: AppTheme.backgroundColor,
      child: Consumer<HabitProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: AppTheme.errorColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载失败: ${provider.error}',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          final habits = provider.habits;
          if (habits.isEmpty) {
            return _buildEmptyState(l);
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            color: AppTheme.primaryColor,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 标题区域
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.event_repeat_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '习惯',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${habits.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 习惯列表
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final habit = habits[index];
                        return HabitCard(
                          habit: habit,
                          onRecord: () => _recordHabit(habit),
                          onSettings: () => _openSettings(habit),
                        );
                      },
                      childCount: habits.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 空状态 - 带引导
  Widget _buildEmptyState(AppLocalizations l) {
    return EmptyStateWidget(
      icon: Icons.event_repeat_rounded,
      title: l.isZh ? '暂无习惯' : 'No Habits',
      subtitle: l.isZh ? '创建一个习惯开始追踪你的日常' : 'Create a habit to track your routine',
      actionLabel: l.isZh ? '创建习惯' : 'Create Habit',
      onAction: _openCreateHabit,
    );
  }

  /// 打开创建习惯
  void _openCreateHabit() {
    showDialog(
      context: context,
      builder: (context) => HabitSettingsDialog(
        habit: Habit(
          id: '',
          title: '',
          triggerType: 'interval',
          isEnabled: true,
          iconCode: 0x1F4A7, // 💧
          voiceEnabled: true,
          soundEnabled: true,
          vibrationEnabled: true,
        ),
      ),
    );
  }

  /// 记录习惯完成
  Future<void> _recordHabit(Habit habit) async {
    if (!habit.needsRecord) {
      _showClockReminder(habit);
      return;
    }

    final provider = context.read<HabitProvider>();
    await provider.logCompletion(habit.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('${habit.title} 已记录'),
            ],
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 显示打卡提醒
  void _showClockReminder(Habit habit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(
              String.fromCharCode(habit.iconCode),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 8),
            Text(habit.title),
          ],
        ),
        content: Text(habit.voiceText ?? '该打卡了！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 打开设置对话框
  void _openSettings(Habit habit) {
    showDialog(
      context: context,
      builder: (context) => HabitSettingsDialog(habit: habit),
    );
  }
}
