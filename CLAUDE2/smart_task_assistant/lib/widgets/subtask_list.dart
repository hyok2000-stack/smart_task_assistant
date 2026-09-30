import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import 'task_card.dart';

class SubtaskList extends StatelessWidget {
  final Task parentTask;
  final List<Task> subtasks;
  final VoidCallback? onAddSubtask;
  final void Function(Task)? onSubtaskTap;

  const SubtaskList({
    super.key,
    required this.parentTask,
    required this.subtasks,
    this.onAddSubtask,
    this.onSubtaskTap,
  });

  @override
  Widget build(BuildContext context) {
    final completed = subtasks.where((t) => t.isCompleted).length;
    final total = subtasks.length;
    final progress = total > 0 ? completed / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          if (total > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1.0 ? AppTheme.successColor : AppTheme.primaryColor,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$completed/$total',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // Subtask cards
          for (final subtask in subtasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 1,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TaskCard(
                      task: subtask,
                      compact: true,
                      onTap: onSubtaskTap != null ? () => onSubtaskTap!(subtask) : null,
                    ),
                  ),
                ],
              ),
            ),
          // Add subtask button - 44px minimum tap target
          if (onAddSubtask != null)
            InkWell(
              onTap: onAddSubtask,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: AppTheme.primaryColor),
                    SizedBox(width: 4),
                    Text(
                      '添加子任务',
                      style: TextStyle(fontSize: 13, color: AppTheme.primaryColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
