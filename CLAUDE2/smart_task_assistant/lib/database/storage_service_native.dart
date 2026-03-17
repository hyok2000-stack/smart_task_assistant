/// 原生平台存储服务实现
/// 使用SQLite数据库

import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'database_helper.dart';
import '../models/task.dart';
import '../models/tag.dart';

/// 原生平台存储实现（使用SQLite）
class NativeStorageService implements StorageService {
  final DatabaseHelper _db = DatabaseHelper();

  @override
  Future<void> init() async {
    debugPrint('===== NativeStorageService.init 开始 =====');

    try {
      // 检查数据库文件是否存在
      final dbExists = await _db.databaseExists();
      debugPrint('数据库文件存在: $dbExists');
      debugPrint('数据库路径: ${await _db.getDatabasePath()}');

      // 获取数据库实例（会自动初始化）
      await _db.database;
      debugPrint('数据库连接已建立');

      // 确保默认标签存在
      await _ensureDefaultTags();

      debugPrint('===== NativeStorageService.init 完成 =====');
    } catch (e) {
      debugPrint('❌ NativeStorageService.init 出错: $e');
      debugPrint('❌ 错误堆栈: ${StackTrace.current}');
      rethrow; // 重新抛出错误，让上层处理
    }
  }

  /// 确保默认标签存在
  Future<void> _ensureDefaultTags() async {
    final tags = await _db.getAllTags();
    final existingIds = tags.map((t) => t.id).toSet();
    final existingNames = tags.map((t) => t.name).toSet();

    // 使用统一的默认标签列表
    final defaultTags = Tag.getDefaultTags();

    // 检查并插入缺失的默认标签
    for (var tag in defaultTags) {
      if (!existingIds.contains(tag.id) && !existingNames.contains(tag.name)) {
        await _db.insertTag(tag);
        debugPrint('插入缺失的默认标签: ${tag.name}');
      }
    }
  }

  @override
  Future<void> insertTask(Task task) => _db.insertTask(task);

  @override
  Future<List<Task>> getAllTasks() => _db.getAllTasks();

  @override
  Future<void> updateTask(Task task) => _db.updateTask(task);

  @override
  Future<void> deleteTask(String id) => _db.deleteTask(id);

  @override
  Future<void> insertTag(Tag tag) => _db.insertTag(tag);

  @override
  Future<List<Tag>> getAllTags() => _db.getAllTags();

  @override
  Future<void> updateTag(Tag tag) => _db.updateTag(tag);

  @override
  Future<void> deleteTag(String id) => _db.deleteTag(id);

  @override
  Future<Map<String, int>> getTaskStats() => _db.getTaskStats();

  @override
  Future<List<Task>> getOverdueTasks() => _db.getOverdueTasks();
}

/// 创建原生存储服务实例
StorageService createNativeStorageService() {
  return NativeStorageService();
}
