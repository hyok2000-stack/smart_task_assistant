import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/sync_queue_item.dart';
import '../providers/task_provider.dart';
import '../services/backend_api_service.dart';
import '../services/sync_queue_service.dart';

class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('同步中心')),
      body: Consumer<TaskProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusCard(context, provider),
              const SizedBox(height: 16),
              _buildSyncButton(context, provider),
              const SizedBox(height: 24),
              _buildQueueSection(context, provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, TaskProvider provider) {
    final backend = BackendApiService.instance;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('同步状态', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: backend.isLoggedIn ? Icons.cloud_done : Icons.cloud_off,
              label: '登录状态',
              value: backend.isLoggedIn
                  ? (backend.nickname ?? '已登录')
                  : '未登录',
              valueColor: backend.isLoggedIn ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.dns_outlined,
              label: '后端地址',
              value: backend.baseUrl,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.devices_other_outlined,
              label: '设备 ID',
              value: backend.deviceId ?? '尚未绑定',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.access_time,
              label: '最后同步',
              value: provider.lastBackendSyncAt != null
                  ? DateFormat('yyyy-MM-dd HH:mm:ss')
                      .format(provider.lastBackendSyncAt!)
                  : '从未同步',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              context,
              icon: Icons.upload_outlined,
              label: '待上传',
              value: '${provider.pendingBackendSyncCount}',
            ),
            if (provider.backendSyncError != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                context,
                icon: Icons.error_outline,
                label: '同步失败',
                value: provider.backendSyncError!,
                valueColor: Colors.red,
                trailing: IconButton(
                  tooltip: '复制错误',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyText(context, provider.backendSyncError!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.grey)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildSyncButton(BuildContext context, TaskProvider provider) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: provider.isBackendSyncing
            ? null
            : () async {
                try {
                  await provider.syncAllWithBackend();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('同步成功')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('同步失败: $e')),
                    );
                  }
                }
              },
        icon: provider.isBackendSyncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
        label: Text(provider.isBackendSyncing ? '同步中...' : '立即同步'),
      ),
    );
  }

  Widget _buildQueueSection(BuildContext context, TaskProvider provider) {
    final queue = provider.syncQueue;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('重试队列', style: theme.textTheme.titleMedium),
            const Spacer(),
          if (queue.isNotEmpty) ...[
              TextButton(
                onPressed: () async {
                  await SyncQueueService.instance.retryAll();
                  await provider.syncAllWithBackend();
                },
                child: const Text('重试全部'),
              ),
              TextButton(
                onPressed: () async {
                  await SyncQueueService.instance.clear();
                  await provider.syncAllWithBackend();
                },
                child: const Text('清空队列'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (queue.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('暂无失败记录', style: TextStyle(color: Colors.grey)),
            ),
          )
        else
          ...queue.map((item) => _buildQueueItem(context, item, provider)),
      ],
    );
  }

  Future<void> _copyText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Widget _buildQueueItem(
    BuildContext context,
    SyncQueueItem item,
    TaskProvider provider,
  ) {
    final typeLabel = _typeLabel(item.type);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.error_outline,
          color: Colors.orange[700],
          size: 20,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                typeLabel,
                style: TextStyle(fontSize: 12, color: Colors.blue[700]),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '重试 ${item.retryCount} 次',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制错误',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyText(context, item.error!),
                  ),
                ],
              ),
            Text(
              DateFormat('MM-dd HH:mm').format(item.createdAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'task_push':
        return '任务推送';
      case 'task_delete':
        return '任务删除';
      case 'comment_push':
        return '评论推送';
      case 'distribution_ack':
        return '分发确认';
      default:
        return type;
    }
  }
}
