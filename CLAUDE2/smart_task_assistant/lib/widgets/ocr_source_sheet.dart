import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// OCR 图片来源选择底部弹窗（拍照 / 相册）。
///
/// add_task_screen 与 quick_add_modal 共用；
/// 返回 true=拍照、false=相册、null=用户取消。
Future<bool?> showOcrSourcePicker(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined,
                color: AppTheme.primaryColor),
            title: const Text('拍照识别'),
            subtitle: const Text('拍摄含有任务信息的图片'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppTheme.primaryColor),
            title: const Text('从相册选择'),
            subtitle: const Text('选择已有图片识别文字'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
