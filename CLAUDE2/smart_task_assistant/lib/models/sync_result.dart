import 'package:flutter/material.dart';

/// 同步结果详情，记录服务端与本地之间各项差异
class SyncResult {
  final List<String> addedTitles;
  final List<String> updatedTitles;
  final List<String> deletedTitles;
  final int conflictCount;

  const SyncResult({
    this.addedTitles = const [],
    this.updatedTitles = const [],
    this.deletedTitles = const [],
    this.conflictCount = 0,
  });

  bool get hasChanges =>
      addedTitles.isNotEmpty ||
      updatedTitles.isNotEmpty ||
      deletedTitles.isNotEmpty;

  int get totalChanges =>
      addedTitles.length + updatedTitles.length + deletedTitles.length;

  /// 摘要文字，如 "新增 2、更新 3、删除 1"
  String toSummaryString() {
    final parts = <String>[];
    if (addedTitles.isNotEmpty) parts.add('新增 ${addedTitles.length}');
    if (updatedTitles.isNotEmpty) parts.add('更新 ${updatedTitles.length}');
    if (deletedTitles.isNotEmpty) parts.add('删除 ${deletedTitles.length}');
    if (parts.isEmpty) return '同步完成，无变更';
    return '同步完成，${parts.join('、')}';
  }
}

/// 同步报告对话框 — 分类展示新增/更新/删除的任务标题
Future<void> showSyncReportDialog(BuildContext context, SyncResult result) {
  if (!result.hasChanges) {
    // 无变更 → 仅 SnackBar，不弹对话框
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.toSummaryString())),
    );
    return Future.value();
  }
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.sync_rounded, color: Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          const Text('同步报告', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width > 400 ? 400 : double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.toSummaryString(),
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 16),
              if (result.addedTitles.isNotEmpty)
                _buildSection(Icons.add_circle_outline, Colors.green, '服务端新增', result.addedTitles),
              if (result.updatedTitles.isNotEmpty)
                _buildSection(Icons.update, Colors.orange, '服务端更新', result.updatedTitles),
              if (result.deletedTitles.isNotEmpty)
                _buildSection(Icons.delete_outline, Colors.red, '服务端删除', result.deletedTitles),
              if (result.conflictCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_problem, size: 18, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text('${result.conflictCount} 个任务存在冲突',
                          style: const TextStyle(fontSize: 13, color: Colors.orange)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Widget _buildSection(IconData icon, Color color, String title, List<String> items) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            const SizedBox(width: 4),
            Text('(${items.length})', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map((name) => Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Text('• $name', style: const TextStyle(fontSize: 13)),
        )),
      ],
    ),
  );
}
