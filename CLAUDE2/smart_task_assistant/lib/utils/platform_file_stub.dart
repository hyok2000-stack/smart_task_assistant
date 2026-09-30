import 'dart:io';

Future<void> deleteFile(String path) async {}

/// 平台特定的文件操作工具（Stub 版本）
/// 这个文件在没有具体实现的平台使用

/// Web 文件下载（非 Web 平台实现）
void downloadFile(String content, String fileName, String mimeType) {
  // 非平台平台不执行任何操作
}

/// Web 文件选择器（非 Web 平台实现）
void selectFile({
  required String accept,
  required void Function(String content, String fileName) onFileSelected,
  required void Function(String error) onError,
}) {
  // 非平台平台不执行任何操作
  onError('此功能仅在 Web 平台可用');
}

/// 获取程序文档目录
Future<Directory> getAppDocumentsDirectory() async {
  throw UnimplementedError('此功能需要在移动端实现');
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
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 获取程序目录下的所有导出文件列表
/// 返回文件信息列表：[{'fileName': 'xxx.json', 'filePath': '/path/to/xxx.json', 'fileSize': 12345, 'modifiedTime': DateTime}]
Future<List<Map<String, dynamic>>> getExportFilesList() async {
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 从指定路径导入数据
/// [filePath] 文件路径
/// 返回包含文件内容和文件名的Map
Future<Map<String, String>?> importDataFromPath(String filePath) async {
  throw UnimplementedError('此功能需要在移动端实现');
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
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 导入数据（移动端实现 - 已废弃）
/// 返回包含文件内容和文件名的Map
@Deprecated('请使用 getExportFilesList 和 importDataFromPath 替代')
Future<Map<String, String>?> importDataNative() async {
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 获取文件名（移动端实现）
/// 返回选择的文件名（已废弃，请使用 importDataNative）
@Deprecated('请使用 importDataNative 替代')
Future<String?> pickFileNameNative() async {
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 清除所有导出文件
/// 删除程序目录下所有的JSON导出文件
Future<void> clearExportFiles() async {
  throw UnimplementedError('此功能需要在移动端实现');
}
