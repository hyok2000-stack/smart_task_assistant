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

/// 获取程序文档目录
Future<Directory> getAppDocumentsDirectory() async {
  return await getApplicationDocumentsDirectory();
}

/// 导出数据到程序目录（移动端实现）
/// [data] 要导出的数据字符串
/// [fileName] 文件名
/// [mimeType] MIME类型
/// 返回保存的文件路径
Future<String> exportDataToAppDir({
  required String data,
  required String fileName,
  String mimeType = 'application/json',
}) async {
  // 获取程序文档目录
  final directory = await getAppDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(data);
  return file.path;
}

/// 获取程序目录下的所有导出文件列表
/// 返回文件信息列表：[{'fileName': 'xxx.json', 'filePath': '/path/to/xxx.json', 'fileSize': 12345, 'modifiedTime': DateTime}]
Future<List<Map<String, dynamic>>> getExportFilesList() async {
  try {
    final directory = await getAppDocumentsDirectory();

    // 扫描目录下所有JSON文件
    final files = await directory.list().toList();
    final exportFiles = <Map<String, dynamic>>[];

    for (var file in files) {
      if (file is File && file.path.endsWith('.json')) {
        final stat = await file.stat();
        exportFiles.add({
          'fileName': file.uri.pathSegments.last,
          'filePath': file.path,
          'fileSize': stat.size,
          'modifiedTime': stat.modified,
        });
      }
    }

    // 按修改时间降序排序
    exportFiles.sort((a, b) => (b['modifiedTime'] as DateTime)
        .compareTo(a['modifiedTime'] as DateTime));

    return exportFiles;
  } catch (e) {
    print('获取导出文件列表失败: $e');
    return [];
  }
}

/// 从指定路径导入数据
/// [filePath] 文件路径
/// 返回包含文件内容和文件名的Map
Future<Map<String, String>?> importDataFromPath(String filePath) async {
  try {
    final file = File(filePath);
    final content = await file.readAsString();
    final fileName = file.uri.pathSegments.last;
    return {
      'content': content,
      'fileName': fileName,
    };
  } catch (e) {
    print('导入数据失败: $e');
    return null;
  }
}

/// 导出数据（移动端实现 - 已废弃）
/// [data] 要导出的数据字符串
/// [fileName] 文件名
/// [mimeType] MIME类型
@Deprecated('请使用 exportDataToAppDir 替代')
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

/// 导入数据（移动端实现 - 已废弃）
/// 返回包含文件内容和文件名的Map
@Deprecated('请使用 getExportFilesList 和 importDataFromPath 替代')
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
