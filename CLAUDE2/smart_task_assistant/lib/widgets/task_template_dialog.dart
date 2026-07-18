import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';

/// 任务模板对话框：列出已保存的模板，支持「从模板创建」和「删除模板」。
///
/// 调用 [showTaskTemplateDialog] 弹出。选择模板后调用
/// [TaskProvider.createTaskFromTemplate] 创建新任务并关闭对话框。
class TaskTemplateDialog extends StatefulWidget {
  const TaskTemplateDialog({super.key});

  /// 弹出模板选择对话框。返回是否成功创建了任务。
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TaskTemplateDialog(),
    );
    return result ?? false;
  }

  @override
  State<TaskTemplateDialog> createState() => _TaskTemplateDialogState();
}

class _TaskTemplateDialogState extends State<TaskTemplateDialog> {
  List<Task> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final provider = context.read<TaskProvider>();
    final templates = await provider.getTaskTemplates();
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _loading = false;
    });
  }

  Future<void> _createFromTemplate(Task template) async {
    final provider = context.read<TaskProvider>();
    try {
      await provider.createTaskFromTemplate(template.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已从模板「${template.title}」创建任务'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(Task template) async {
    final provider = context.read<TaskProvider>();
    await provider.deleteTaskTemplate(template.id);
    _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 拖拽指示器
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.bookmark_rounded, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  '任务模板',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _templates.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        itemCount: _templates.length,
                        itemBuilder: (context, index) {
                          final tpl = _templates[index];
                          return _buildTemplateItem(tpl);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('还没有模板',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          const SizedBox(height: 8),
          Text(
            '在任务详情中「保存为模板」即可快速复用',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateItem(Task tpl) {
    return Dismissible(
      key: ValueKey(tpl.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.errorColor,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTemplate(tpl),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.bookmark_rounded,
              color: AppTheme.primaryColor, size: 20),
        ),
        title: Text(tpl.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (tpl.content?.isNotEmpty == true) tpl.content!,
            '优先级: ${_priorityLabel(tpl.priority)}',
            if (tpl.tagIds.isNotEmpty) '标签: ${tpl.tagIds.length}个',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.add_circle_rounded,
            color: AppTheme.primaryColor),
        onTap: () => _createFromTemplate(tpl),
      ),
    );
  }

  String _priorityLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:
        return '高';
      case TaskPriority.medium:
        return '中';
      case TaskPriority.low:
        return '低';
    }
  }
}
