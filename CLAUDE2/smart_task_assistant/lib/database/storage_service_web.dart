/// Web平台存储服务存根
/// 此文件仅在Web平台编译时使用
library;

import 'storage_service.dart';

/// Web平台不需要原生存储服务，返回null
StorageService createNativeStorageService() {
  throw UnsupportedError('Native storage is not supported on web platform');
}