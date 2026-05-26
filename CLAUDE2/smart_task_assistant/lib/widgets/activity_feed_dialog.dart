import 'package:flutter/material.dart';
import '../services/backend_api_service.dart';
import '../theme/app_theme.dart';

class ActivityFeedDialog extends StatefulWidget {
  const ActivityFeedDialog({super.key});

  @override
  State<ActivityFeedDialog> createState() => _ActivityFeedDialogState();
}

class _ActivityFeedDialogState extends State<ActivityFeedDialog> {
  List<Map<String, dynamic>> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
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
    if (action.contains('create')) return Icons.add_circle_outline;
    if (action.contains('update')) return Icons.edit_rounded;
    if (action.contains('complete')) return Icons.check_circle_outline;
    if (action.contains('delete')) return Icons.delete_outline;
    if (action.contains('comment')) return Icons.chat_bubble_outline;
    return Icons.info_outline;
  }

  Color _actionColor(String action) {
    if (action.contains('create')) return AppTheme.successColor;
    if (action.contains('update')) return AppTheme.infoColor;
    if (action.contains('complete')) return AppTheme.successColor;
    if (action.contains('delete')) return AppTheme.errorColor;
    if (action.contains('comment')) return AppTheme.primaryColor;
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
                const Text(
                  '团队动态',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    if (_activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('暂无动态', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _activities.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
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
            child: Icon(_actionIcon(action), size: 18, color: _actionColor(action)),
          ),
          title: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimaryColor),
              children: [
                TextSpan(text: nickname, style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: ' $action'),
                if (taskTitle.isNotEmpty)
                  TextSpan(text: ' 「$taskTitle」', style: TextStyle(color: AppTheme.primaryColor)),
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
}
