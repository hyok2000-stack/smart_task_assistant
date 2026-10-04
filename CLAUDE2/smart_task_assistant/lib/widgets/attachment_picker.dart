import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';

/// 任务附件选择器。
///
/// 支持多文件选择、复制到应用内部目录、列表展示、删除。
/// 复用 add_task_screen 中语音文件的「复制到内部存储」模式，
/// 确保附件在任务创建后仍可访问。
class AttachmentPicker extends StatefulWidget {
  /// 当前已选附件路径列表
  final List<String> attachmentPaths;

  /// 附件变化回调
  final Future<void> Function(List<String>) onChanged;

  const AttachmentPicker({
    super.key,
    required this.attachmentPaths,
    required this.onChanged,
  });

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  List<String> get _paths => widget.attachmentPaths;
  bool _picking = false;

  /// 直接调用 onChanged 回调（同步），不做异步包装——
  /// onChanged 是 ValueChanged<List<String>>（同步），父组件的 setState 会在
  /// 当前 frame 结束后执行，不会在 build 过程中触发 rebuild。
  void _update(List<String> paths) {
    widget.onChanged(paths);
  }

  Future<void> _pickFiles() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) {
        if (mounted) setState(() => _picking = false);
        return;
      }

      final newPaths = <String>[];
      for (final file in files) {
        // v13 API：identifier 已移除，path 为空时退回内容 URI
        final ref = file.path ?? file.uri.toString();
        if (ref.isNotEmpty) {
          newPaths.add(ref);
          // content URI 需要持久化读取权限，否则 App 重启后无法打开
          if (ref.startsWith('content://')) {
            try {
              const channel = MethodChannel('com.smarttask.smart_task_assistant/file');
              await channel.invokeMethod('persistUri', {'uri': ref});
            } catch (e) {
              debugPrint('持久化附件 URI 权限失败（非致命）: $e');
            }
          }
          debugPrint('附件已添加: name=${file.name}, ref=$ref');
        } else {
          debugPrint('附件无可用引用: name=${file.name}, '
              'hasPath=${file.path != null}, '
              'uri=${file.uri}');
        }
      }

      if (newPaths.isNotEmpty) {
        _update([..._paths, ...newPaths]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法获取该文件的引用，请尝试从文件管理器中选择'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('附件选择异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加附件失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _removeAt(int index) async {
    final newList = List<String>.from(_paths);
    newList.removeAt(index);
    _update(newList);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选附件列表
        if (_paths.isNotEmpty) ...[
          for (int i = 0; i < _paths.length; i++)
            _buildAttachmentItem(_paths[i], i),
          const SizedBox(height: 8),
        ],
        // 添加按钮
        InkWell(
          onTap: _picking ? null : _pickFiles,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _picking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file,
                        size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  _paths.isEmpty ? '添加附件' : '继续添加',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 提取文件名——兼容 content:// URI 和普通路径
  String _extractFileName(String path) {
    // content://com.android.providers.../document/xxx%2F文件名.pdf
    if (path.startsWith('content://')) {
      // 尝试从 URI 最后一段提取
      final decoded = Uri.decodeFull(path);
      final lastSegment = decoded.split('/').last;
      // 去掉可能的 primary%3A 前缀
      if (lastSegment.contains('%2F')) {
        return lastSegment.split('%2F').last;
      }
      return lastSegment.isNotEmpty ? lastSegment : '附件';
    }
    return path.split(Platform.pathSeparator).last;
  }

  /// 用系统应用打开附件。
  /// content:// URI 通过原生 Intent.ACTION_VIEW 打开（OpenFilex 不支持 content URI）。
  Future<void> _openAttachment(String path) async {
    try {
      const channel = MethodChannel('com.smarttask.smart_task_assistant/file');
      await channel.invokeMethod('openFile', {'uri': path});
    } on PlatformException catch (e) {
      debugPrint('打开附件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.code == 'OPEN_FAILED'
                ? '无法打开此文件，可能没有对应的应用'
                : '打开失败: ${e.message}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('打开附件异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  Widget _buildAttachmentItem(String path, int index) {
    final fileName = _extractFileName(path);
    final ext = fileName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (isImage && !path.startsWith('content://'))
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.file(File(path),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _typeIcon(ext)),
            )
          else
            _typeIcon(ext),
          const SizedBox(width: 8),
          // 点击文件名可打开预览
          Expanded(
            child: GestureDetector(
              onTap: () => _openAttachment(path),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.primaryColor,
                          decoration: TextDecoration.underline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  FutureBuilder<String>(
                    future: _fileSize(path),
                    builder: (_, snapshot) => Text(snapshot.data ?? '读取大小中…',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ),
                ],
              ),
            ),
          ),
          // 打开按钮
          GestureDetector(
            onTap: () => _openAttachment(path),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.open_in_new, size: 16, color: Colors.blue[400]),
            ),
          ),
          // 删除按钮
          GestureDetector(
            onTap: () => _removeAt(index),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeIcon(String ext) {
    final icon = switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.description_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
      'mp3' || 'wav' || 'm4a' => Icons.audio_file_outlined,
      'mp4' || 'mov' || 'avi' => Icons.video_file_outlined,
      'jpg' || 'jpeg' || 'png' || 'webp' || 'gif' => Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return Icon(icon, size: 28, color: Colors.grey[600]);
  }

  Future<String> _fileSize(String path) async {
    if (path.startsWith('content://')) return '系统文件';
    try {
      final bytes = await File(path).length();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } catch (_) {
      return '大小未知';
    }
  }
}
