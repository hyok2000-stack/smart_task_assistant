import 'package:flutter/material.dart';
import '../models/task.dart';
import '../screens/add_task_screen.dart';
import '../theme/app_theme.dart';

/// 提醒后续操作对话框
class ReminderActionDialog extends StatelessWidget {
  final Task task;
  /// onAction 回调参数:
  /// - reminderMinutes: 新的提前提醒时间（分钟），更新任务的提醒设置
  /// - dismissed: 是否永久关闭提醒
  /// - snoozeMinutes: 稍后提醒的分钟数（临时提醒，不修改任务）
  final Function({int? reminderMinutes, bool dismissed, int? snoozeMinutes}) onAction;

  const ReminderActionDialog({
    super.key,
    required this.task,
    required this.onAction,
  });

  // 稍后提醒选项，不修改任务本身的提前提醒设置
  static const List<Map<String, dynamic>> _timeOptions = [
    {'minutes': 10, 'label': '10分钟后'},
    {'minutes': 30, 'label': '30分钟后'},
    {'minutes': 60, 'label': '1小时后'},
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 标题行
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: AppTheme.warningColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '任务提醒',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '截止时间: ${task.dueTimeDescription}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 任务标题（点击进入编辑页面）
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddTaskScreen(task: task)),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: AppTheme.primaryColor,
                          decorationStyle: TextDecorationStyle.dotted,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.edit_outlined,
                      color: AppTheme.primaryColor.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 稍后提醒按钮
            const Text(
              '稍后提醒',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: _timeOptions.map((option) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option == _timeOptions.last ? 0 : 8,
                    ),
                    child: _buildTimeButton(
                      context: context,
                      label: option['label'] as String,
                      minutes: option['minutes'] as int,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 不再提醒按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  onAction(dismissed: true);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.notifications_off_rounded, size: 18),
                label: const Text('不再提醒此任务'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondaryColor,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 关闭按钮
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  // 只是关闭窗口，稍后会再次提醒
                  onAction();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('关闭'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondaryColor,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTimeButton({
    required BuildContext context,
    required String label,
    required int minutes,
  }) {
    return OutlinedButton(
      onPressed: () {
        // 只设置临时稍后提醒，不修改任务的提前提醒时间
        onAction(snoozeMinutes: minutes);
        Navigator.pop(context);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// 显示提醒对话框的辅助函数
Future<void> showReminderDialog(
  BuildContext context, {
  required Task task,
  required Function({int? reminderMinutes, bool dismissed, int? snoozeMinutes}) onAction,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => ReminderActionDialog(
      task: task,
      onAction: onAction,
    ),
  );
}
