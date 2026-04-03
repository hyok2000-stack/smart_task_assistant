import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_settings_dialog.dart';

/// 习惯标签页
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('习惯'),
        centerTitle: true,
      ),
      body: Consumer<HabitProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('加载失败: ${provider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          final habits = provider.habits;
          if (habits.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '暂无习惯',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: habits.length,
              itemBuilder: (context, index) {
                final habit = habits[index];
                return HabitCard(
                  habit: habit,
                  onRecord: () => _recordHabit(habit),
                  onSettings: () => _openSettings(habit),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 记录习惯完成
  Future<void> _recordHabit(Habit habit) async {
    if (!habit.needsRecord) {
      // 打卡类习惯只显示提醒
      _showClockReminder(habit);
      return;
    }

    final provider = context.read<HabitProvider>();
    await provider.logCompletion(habit.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${habit.title} 已记录'),
          backgroundColor: Colors.green,
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