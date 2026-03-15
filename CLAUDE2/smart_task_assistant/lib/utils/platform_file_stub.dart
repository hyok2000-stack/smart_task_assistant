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

/// 导出数据（移动端实现）
Future<void> exportDataNative({
  required String data,
  required String fileName,
  String mimeType = 'application/json',
}) async {
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 导入数据（移动端实现）
/// 返回包含文件内容和文件名的Map
Future<Map<String, String>?> importDataNative() async {
  throw UnimplementedError('此功能需要在移动端实现');
}

/// 获取文件名（移动端实现）
/// 返回选择的文件名（已废弃，请使用 importDataNative）
@Deprecated('请使用 importDataNative 替代')
Future<String?> pickFileNameNative() async {
  throw UnimplementedError('此功能需要在移动端实现');
}
