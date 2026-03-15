import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';

/// 新增标签对话框
class TagCreateDialog extends StatefulWidget {
  const TagCreateDialog({super.key});

  @override
  State<TagCreateDialog> createState() => _TagCreateDialogState();
}

class _TagCreateDialogState extends State<TagCreateDialog> {
  final _controller = TextEditingController();
  String _selectedColor = '#6366F1';
  bool _isCreating = false;

  final List<String> _colorOptions = [
    '#6366F1',
    '#8B5CF6',
    '#EC4899',
    '#EF4444',
    '#F59E0B',
    '#10B981',
    '#06B6D4',
    '#3B82F6',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createTag() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      final provider = context.read<TaskProvider>();
      final existing = provider.tags.any(
        (t) => t.name.toLowerCase() == name.toLowerCase(),
      );

      if (existing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('标签已存在')),
          );
        }
        setState(() => _isCreating = false);
        return;
      }

      final tag = Tag(
        id: const Uuid().v4(),
        name: name,
        color: _selectedColor,
        sortOrder: provider.tags.length,
      );

      await provider.addTag(tag);

      if (mounted) {
        Navigator.pop(context, tag);
      }
    } catch (e) {
      debugPrint('创建标签失败: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新建标签',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '输入标签名称',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _createTag(),
            ),
            const SizedBox(height: 20),
            const Text('选择颜色',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colorOptions.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                    ),
                    child: isSelected
                        ? Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isCreating ? null : _createTag,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('创建'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<Tag?> showTagCreateDialog(BuildContext context) {
  return showDialog<Tag>(
    context: context,
    builder: (context) => const TagCreateDialog(),
  );
}
