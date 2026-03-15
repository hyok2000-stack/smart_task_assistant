/// 平台特定的 Web 文件操作工具
/// 这个文件只在 Web 平台使用

import 'dart:html' as html;

/// Web 文件下载
void downloadFile(String content, String fileName, String mimeType) {
  final bytes = content.runes.toList();
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}

/// Web 文件选择器
void selectFile({
  required String accept,
  required void Function(String content, String fileName) onFileSelected,
  required void Function(String error) onError,
}) {
  try {
    final uploadInput = html.InputElement(type: 'file')
      ..accept = accept
      ..click();

    uploadInput.onChange.listen((e) async {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) return;

      try {
        final file = files[0];
        final reader = html.FileReader();

        reader.onLoad.listen((e) {
          final content = reader.result as String;
          onFileSelected(content, file.name);
        });

        reader.onError.listen((e) {
          onError('读取文件失败');
        });

        reader.readAsText(file);
      } catch (e) {
        onError('选择文件失败: $e');
      }
    });
  } catch (e) {
    onError('创建文件选择器失败: $e');
  }
}
