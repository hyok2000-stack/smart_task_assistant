import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 文件下载（移动端实现 - 不支持，返回空实现）
void downloadFile(String content, String fileName, String mimeType) {
  // 移动端不支持直接下载，使用 exportDataNative 替代
}

/// 文件选择器（移动端实现 - 不支持，返回空实现）
void selectFile({
  required String accept,
  required void Function(String content, String fileName) onFileSelected,
  required void Function(String error) onError,
}) {
  // 移动端不支持这种选择器，使用 importDataNative 替代
  onError('移动端请使用系统文件选择器');
}

/// 导出数据（移动端实现）
/// [data] 要导出的数据字符串
/// [fileName] 文件名
/// [mimeType] MIME类型
Future<void> exportDataNative({
  required String data,
  required String fileName,
  String mimeType = 'application/json',
}) async {
  // 移动端使用分享方式
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(data);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: '任务数据导出',
    text: '这是智能任务助手导出的数据文件',
  );
}

/// 导入数据（移动端实现）
/// 返回包含文件内容和文件名的Map
Future<Map<String, String>?> importDataNative() async {
  // 移动端使用文件选择器
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );

  if (result != null && result.files.single.path != null) {
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final fileName = result.files.single.name;
    return {
      'content': content,
      'fileName': fileName,
    };
  }

  return null;
}

/// 获取文件名（移动端实现）
/// 返回选择的文件名（已废弃，请使用 importDataNative）
@Deprecated('请使用 importDataNative 替代')
Future<String?> pickFileNameNative() async {
  return null;
}
