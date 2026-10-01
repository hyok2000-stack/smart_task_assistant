/// 平台特定的 Web 文件操作工具
/// 这个文件只在 Web 平台使用
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> deleteFile(String path) async {}

/// 导出到程序目录（Web 无本地目录：改用浏览器下载，返回提示性文件名）
Future<String?> exportDataToAppDir({
  required String data,
  required String fileName,
}) async {
  downloadFile(data, fileName, 'application/json');
  return fileName;
}

/// Web 文件下载
void downloadFile(String content, String fileName, String mimeType) {
  final bytes = Uint8List.fromList(content.runes.toList());
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  // 不经变量直接触发下载（anchor 的值本身无用，click() 才是副作用）
  final anchor = web.HTMLAnchorElement();
  anchor.href = url;
  anchor.setAttribute('download', fileName);
  anchor.click();

  web.URL.revokeObjectURL(url);
}

/// Web 文件选择器
void selectFile({
  required String accept,
  required void Function(String content, String fileName) onFileSelected,
  required void Function(String error) onError,
}) {
  try {
    final uploadInput = web.HTMLInputElement();
    uploadInput.type = 'file';
    uploadInput.accept = accept;
    uploadInput.click();

    uploadInput.addEventListener(
      'change',
      ((web.Event _) {
        final files = uploadInput.files;
        if (files == null || files.length == 0) return;

        try {
          final file = files.item(0)!;
          final reader = web.FileReader();

          reader.addEventListener('load', ((web.ProgressEvent _) {
            // readAsText 结果为字符串：JSAny? → String
            final content = reader.result?.dartify()?.toString() ?? '';
            onFileSelected(content, file.name);
          }).toJS);

          reader.addEventListener('error', ((web.ProgressEvent _) {
            onError('读取文件失败');
          }).toJS);

          reader.readAsText(file);
        } catch (e) {
          onError('选择文件失败: $e');
        }
      }).toJS,
    );
  } catch (e) {
    onError('创建文件选择器失败: $e');
  }
}

/// 清除所有导出文件
/// Web平台没有本地文件，此方法为空实现
Future<void> clearExportFiles() async {
  // Web平台使用下载方式，没有本地文件需要清除
}
