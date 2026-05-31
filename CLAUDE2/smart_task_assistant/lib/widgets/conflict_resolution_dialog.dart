import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/task_provider.dart';
import '../services/backend_api_service.dart';

class ConflictResolutionDialog extends StatelessWidget {
  const ConflictResolutionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final conflicts = provider.conflicts;
        if (conflicts.isEmpty) {
          // 冲突已全部解决 — 延迟关闭对话框
          // 只在当前路由仍是最顶层时才 pop，避免与 _resolveAll 的 pop 竞争导致双重 pop（黑屏）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context);
            if (route != null && route.isCurrent) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }

        return Dialog(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_problem, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        '同步冲突 (${conflicts.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: conflicts.length,
                    itemBuilder: (context, index) {
                      return _ConflictCard(
                        conflict: conflicts[index],
                        onResolve: (keepLocal) async {
                          await provider.resolveConflict(
                            conflicts[index].taskId,
                            keepLocal: keepLocal,
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _resolveAll(context, provider, keepLocal: true),
                              icon: const Icon(Icons.cloud_upload, size: 16),
                              label: const Text('全部保留本地'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _resolveAll(context, provider, keepLocal: false),
                              icon: const Icon(Icons.cloud_download, size: 16),
                              label: const Text('全部使用服务器'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('稍后处理'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _resolveAll(BuildContext context, TaskProvider provider, {required bool keepLocal}) async {
    final ids = provider.conflicts.map((c) => c.taskId).toList();
    for (final id in ids) {
      await provider.resolveConflict(id, keepLocal: keepLocal);
    }
    if (context.mounted) Navigator.pop(context);
  }
}

class _ConflictCard extends StatelessWidget {
  final ConflictInfo conflict;
  final Future<void> Function(bool keepLocal) onResolve;

  const _ConflictCard({required this.conflict, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final server = conflict.serverVersion;
    final client = conflict.clientVersion;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            server['title'] ?? client['title'] ?? '未知任务',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildVersionCard('本地版本', client, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildVersionCard('服务器版本', server, Colors.green)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onResolve(true),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
                  child: const Text('保留本地'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onResolve(false),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                  child: const Text('使用服务器'),
                ),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildVersionCard(String label, Map<String, dynamic> data, Color color) {
    final fields = [
      ('状态', data['status']?.toString()),
      ('优先级', data['priority']?.toString()),
      ('内容', data['content']?.toString()),
      ('截止时间', _formatDate(data['dueTime']?.toString())),
      ('版本', data['version']?.toString()),
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12, color: color)),
          const SizedBox(height: 4),
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(f.$1,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ),
                    Expanded(
                      child: Text(f.$2 ?? '-',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String? _formatDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    return dt != null
        ? '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}'
        : iso;
  }
}

Future<void> showConflictDialogIfNeeded(BuildContext context) async {
  final provider = context.read<TaskProvider>();
  if (provider.hasConflicts) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConflictResolutionDialog(),
    );
  }
}
