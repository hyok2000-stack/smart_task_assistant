import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';

/// 回收站：已删除任务的快照，30 天内可恢复，也可彻底删除。
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await DatabaseHelper().getTrashEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _restore(String trashId) async {
    final ok = await context.read<TaskProvider>().restoreFromTrash(trashId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '任务已恢复' : '恢复失败（任务可能已存在同名 ID）')),
    );
    _load();
  }

  Future<void> _purge(String trashId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: const Text('快照将被永久删除，无法再恢复。确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<TaskProvider>().purgeTrashItem(trashId);
    _load();
  }

  Future<void> _emptyAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('所有快照将被永久删除，确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await context.read<TaskProvider>().emptyTrash();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: _emptyAll,
              child: const Text('清空', style: TextStyle(color: AppTheme.errorColor)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('回收站是空的'),
                      SizedBox(height: 4),
                      Text('删除的任务会在这里保留 30 天',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final deletedAt =
                        DateTime.tryParse(entry['deleted_at'] as String? ?? '');
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.task_alt_outlined,
                            color: Colors.grey),
                        title: Text(
                          entry['title'] as String? ?? '（无标题）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: deletedAt == null
                            ? null
                            : Text(
                                '删除于 ${deletedAt.month}/${deletedAt.day} '
                                '${deletedAt.hour.toString().padLeft(2, '0')}:'
                                '${deletedAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 12),
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '恢复',
                              icon: const Icon(Icons.restore_rounded,
                                  color: AppTheme.successColor),
                              onPressed: () => _restore(entry['id'] as String),
                            ),
                            IconButton(
                              tooltip: '彻底删除',
                              icon: const Icon(Icons.delete_forever_rounded,
                                  color: AppTheme.errorColor),
                              onPressed: () => _purge(entry['id'] as String),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
