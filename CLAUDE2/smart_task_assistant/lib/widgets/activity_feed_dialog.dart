import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../services/task_history_service.dart';
import '../theme/app_theme.dart';

class ActivityFeedDialog extends StatefulWidget {
  final String? taskId;
  final String? taskTitle;
  final DateTime? taskCreatedAt;

  const ActivityFeedDialog({
    super.key,
    this.taskId,
    this.taskTitle,
    this.taskCreatedAt,
  });

  @override
  State<ActivityFeedDialog> createState() => _ActivityFeedDialogState();
}

class _ActivityFeedDialogState extends State<ActivityFeedDialog> {
  List<Map<String, dynamic>> _activities = [];
  List<TaskHistoryEntry> _taskHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      if (widget.taskId != null) {
        final history =
            await TaskHistoryService.instance.getForTask(widget.taskId!);
        if (!history.any((entry) => entry.action == '创建') &&
            widget.taskCreatedAt != null) {
          history.add(TaskHistoryEntry(
            id: 'legacy-created-${widget.taskId}',
            taskId: widget.taskId!,
            action: '创建',
            field: '任务',
            afterValue: widget.taskTitle,
            actorName: '历史数据',
            createdAt: widget.taskCreatedAt!,
          ));
          history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        if (mounted) {
          setState(() {
            _taskHistory = history;
            _isLoading = false;
          });
        }
        return;
      }
      final activities = await BackendApiService.instance.getActivityFeed();
      if (mounted) {
        setState(() {
          _activities = activities;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _actionIcon(String action) {
    if (action.contains('create') || action.contains('创建')) {
      return Icons.add_circle_outline;
    }
    if (action.contains('update') || action.contains('编辑')) {
      return Icons.edit_rounded;
    }
    if (action.contains('complete') || action.contains('状态')) {
      return Icons.check_circle_outline;
    }
    if (action.contains('delete') || action.contains('删除')) {
      return Icons.delete_outline;
    }
    if (action.contains('comment') || action.contains('评论')) {
      return Icons.chat_bubble_outline;
    }
    if (action.contains('归档')) return Icons.archive_outlined;
    if (action.contains('恢复')) return Icons.restore_rounded;
    if (action.contains('指派')) return Icons.person_add_alt_rounded;
    if (action.contains('附件')) return Icons.attach_file_rounded;
    return Icons.info_outline;
  }

  Color _actionColor(String action) {
    if (action.contains('create') || action.contains('创建')) {
      return AppTheme.successColor;
    }
    if (action.contains('update') || action.contains('编辑')) {
      return AppTheme.infoColor;
    }
    if (action.contains('complete') || action.contains('状态')) {
      return AppTheme.successColor;
    }
    if (action.contains('delete') || action.contains('删除')) {
      return AppTheme.errorColor;
    }
    if (action.contains('comment') || action.contains('评论')) {
      return AppTheme.primaryColor;
    }
    return AppTheme.textSecondaryColor;
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.timeline_rounded,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.taskId == null ? '团队动态' : '任务操作历史',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }
    if (widget.taskId != null) return _buildTaskHistory();
    if (_activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('暂无动态',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _activities.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.shade100),
      itemBuilder: (context, index) {
        final a = _activities[index];
        final action = a['action'] as String? ?? '';
        final nickname = a['nickname'] as String? ?? '未知用户';
        final taskTitle = a['taskTitle'] as String? ?? '';
        final createdAt = a['createdAt'] as String?;
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _actionColor(action).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_actionIcon(action),
                size: 18, color: _actionColor(action)),
          ),
          title: RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimaryColor),
              children: [
                TextSpan(
                    text: nickname,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' $action'),
                if (taskTitle.isNotEmpty)
                  TextSpan(
                      text: ' 「$taskTitle」',
                      style: const TextStyle(color: AppTheme.primaryColor)),
              ],
            ),
          ),
          subtitle: Text(
            _formatTime(createdAt),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildTaskHistory() {
    if (_taskHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('暂无该任务的操作记录', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _taskHistory.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final entry = _taskHistory[index];
        final hasChange = entry.beforeValue != entry.afterValue &&
            (entry.beforeValue != null || entry.afterValue != null);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _actionColor(entry.action).withValues(alpha: 0.12),
            child: Icon(_actionIcon(entry.action),
                size: 19, color: _actionColor(entry.action)),
          ),
          title: Text(
              '${entry.actorName} · ${entry.action}${entry.field == '任务' ? '' : ' ${entry.field}'}',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasChange)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '${entry.beforeValue ?? '无'}  →  ${entry.afterValue ?? '无'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              const SizedBox(height: 3),
              Text(_formatExactTime(entry.createdAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  String _formatExactTime(DateTime time) {
    final t = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
