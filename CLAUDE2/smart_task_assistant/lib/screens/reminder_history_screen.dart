import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';

/// 提醒历史：每次提醒触发的记录（前台 + 后台双通道），可追溯错过的提醒。
class ReminderHistoryScreen extends StatefulWidget {
  const ReminderHistoryScreen({super.key});

  @override
  State<ReminderHistoryScreen> createState() => _ReminderHistoryScreenState();
}

class _ReminderHistoryScreenState extends State<ReminderHistoryScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await DatabaseHelper().getReminderLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  String _formatTime(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '';
    final now = DateTime.now();
    final dateStr = (dt.year == now.year && dt.month == now.month && dt.day == now.day)
        ? '今天'
        : '${dt.month}/${dt.day}';
    return '$dateStr ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('提醒历史')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded,
                          size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('还没有提醒记录'),
                      SizedBox(height: 4),
                      Text('每次任务/习惯提醒触发后都会记录在这里',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isHabit = log['type'] == 'habit';
                      final source = log['source'] == 'native' ? '后台' : '应用内';
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: Icon(
                            isHabit
                                ? Icons.repeat_rounded
                                : Icons.notifications_active_rounded,
                            color: isHabit
                                ? AppTheme.primaryColor
                                : AppTheme.warningColor,
                          ),
                          title: Text(
                            log['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$source提醒 · ${_formatTime(log['shown_at'] as String?)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
