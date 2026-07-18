/// 原生平台存储服务实现
/// 使用SQLite数据库

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import 'database_helper.dart';
import '../models/task.dart';
import '../models/tag.dart';

/// 原生平台存储实现（使用SQLite）
class NativeStorageService implements StorageService {
  final DatabaseHelper _db = DatabaseHelper();
  static const String _backupKey = 'native_auto_backup_v1';

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

  /// 自动备份（Native 端）：将当前所有任务+标签导出为 JSON 快照存入 SharedPreferences。
  /// 作为 SQLite 之外的额外恢复途径（例如迁移失败、数据库损坏时）。
  @override
  Future<void> autoBackup() async {
    try {
      final tasks = await _db.getAllTasks();
      final tags = await _db.getAllTags();
      final backupData = {
        'version': '1.0',
        'platform': 'native',
        'backupTime': DateTime.now().toIso8601String(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
      };
      final encoded = jsonEncode(backupData);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_backupKey, encoded);
      debugPrint('原生自动备份完成: ${tasks.length} 个任务, ${tags.length} 个标签');
    } catch (e) {
      debugPrint('原生自动备份失败: $e');
    }
  }

  /// 获取自动备份数据
  @override
  Future<Map<String, dynamic>?> getAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_backupKey);
      if (json == null) return null;
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('读取原生备份失败: $e');
      return null;
    }
  }

  /// 从备份数据恢复（覆盖当前任务和标签）
  @override
  Future<bool> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      // 恢复标签
      if (backupData['tags'] != null) {
        final List<dynamic> tagsJson = backupData['tags'];
        for (final json in tagsJson) {
          await _db.insertTag(Tag.fromJson(json as Map<String, dynamic>));
        }
      }
      // 恢复任务
      if (backupData['tasks'] != null) {
        final List<dynamic> tasksJson = backupData['tasks'];
        for (final json in tasksJson) {
          await _db.insertTask(Task.fromJson(json as Map<String, dynamic>));
        }
      }
      debugPrint('原生从备份恢复完成');
      return true;
    } catch (e) {
      debugPrint('原生从备份恢复失败: $e');
      return false;
    }
  }
}

/// 创建原生存储服务实例
StorageService createNativeStorageService() {
  return NativeStorageService();
}
