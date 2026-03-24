import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/tag.dart';
import 'storage_service_native.dart'
    if (dart.library.html) 'storage_service_web.dart';

/// 跨平台存储服务
/// Web端使用SharedPreferences，原生端使用SQLite
abstract class StorageService {
  Future<void> init();
  Future<void> insertTask(Task task);
  Future<List<Task>> getAllTasks();
  Future<void> updateTask(Task task);
  Future<void> deleteTask(String id);
  Future<void> insertTag(Tag tag);
  Future<List<Tag>> getAllTags();
  Future<void> updateTag(Tag tag);
  Future<void> deleteTag(String id);
  Future<Map<String, int>> getTaskStats();
  Future<List<Task>> getOverdueTasks();
}

/// Web端存储实现（使用SharedPreferences）
class WebStorageService implements StorageService {
  static const String _tasksKey = 'tasks';
  static const String _tagsKey = 'tags';
  static const String _backupKey = 'auto_backup'; // 自动备份键

  SharedPreferences? _prefs;
  List<Task> _tasks = [];
  List<Tag> _tags = [];

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadTasks();
    _loadTags();

    // 如果没有标签，插入默认标签
    if (_tags.isEmpty) {
      await _insertDefaultTags();
    }
  }

  void _loadTasks() {
    final tasksJson = _prefs?.getString(_tasksKey);
    if (tasksJson != null) {
      final List<dynamic> decoded = jsonDecode(tasksJson);
      _tasks = decoded.map((json) => Task.fromJson(json)).toList();
    }
  }

  void _loadTags() {
    final tagsJson = _prefs?.getString(_tagsKey);
    if (tagsJson != null) {
      final List<dynamic> decoded = jsonDecode(tagsJson);
      _tags = decoded.map((json) => Tag.fromJson(json)).toList();
    }
  }

  Future<void> _saveTasks() async {
    final encoded = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await _prefs?.setString(_tasksKey, encoded);
  }

  Future<void> _saveTags() async {
    final encoded = jsonEncode(_tags.map((t) => t.toJson()).toList());
    await _prefs?.setString(_tagsKey, encoded);
  }

  Future<void> _insertDefaultTags() async {
    final defaultTags = Tag.getDefaultTags();

    for (var tag in defaultTags) {
      _tags.add(tag);
    }
    await _saveTags();
  }

  @override
  Future<void> insertTask(Task task) async {
    debugPrint('WebStorageService.insertTask: ${task.title}');
    _tasks.insert(0, task);
    await _saveTasks();
    debugPrint('WebStorageService.insertTask 完成，任务数: ${_tasks.length}');
  }

  @override
  Future<List<Task>> getAllTasks() async {
    return List.from(_tasks); // 返回副本，避免引用共享问题
  }

  @override
  Future<void> updateTask(Task task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      await _saveTasks();
    }
  }

  @override
  Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _saveTasks();
  }

  @override
  Future<void> insertTag(Tag tag) async {
    // 检查是否已存在相同ID或相同名称的标签
    final existingById = _tags.any((t) => t.id == tag.id);
    final existingByName = _tags.any(
      (t) => t.name.toLowerCase() == tag.name.toLowerCase(),
    );

    if (existingById || existingByName) {
      debugPrint('标签已存在，跳过创建: ${tag.name}');
      return;
    }

    _tags.add(tag);
    await _saveTags();
    debugPrint('标签创建成功: ${tag.name}, 总数: ${_tags.length}');
  }

  @override
  Future<List<Tag>> getAllTags() async {
    return _tags;
  }

  @override
  Future<void> updateTag(Tag tag) async {
    final index = _tags.indexWhere((t) => t.id == tag.id);
    if (index != -1) {
      _tags[index] = tag;
      await _saveTags();
    }
  }

  @override
  Future<void> deleteTag(String id) async {
    _tags.removeWhere((t) => t.id == id);
    await _saveTags();
  }

  @override
  Future<Map<String, int>> getTaskStats() async {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isCompleted).length;
    final pending = _tasks.where((t) => t.status == TaskStatus.pending).length;
    final inProgress = _tasks
        .where((t) => t.status == TaskStatus.inProgress)
        .length;
    final overdue = _tasks.where((t) => t.isOverdue).length;

    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'inProgress': inProgress,
      'overdue': overdue,
    };
  }

  @override
  Future<List<Task>> getOverdueTasks() async {
    // 逾期任务：未完成、未取消且已过截止时间
    return _tasks
        .where(
          (t) =>
              !t.isCompleted && t.status != TaskStatus.cancelled && t.isOverdue,
        )
        .toList();
  }

  /// 自动备份数据到本地存储
  Future<void> autoBackup() async {
    try {
      final backupData = {
        'version': '1.0',
        'backupTime': DateTime.now().toIso8601String(),
        'tasks': _tasks.map((t) => t.toJson()).toList(),
        'tags': _tags.map((t) => t.toJson()).toList(),
      };

      final encoded = const JsonEncoder.withIndent('  ').convert(backupData);
      await _prefs?.setString(_backupKey, encoded);
      debugPrint('自动备份完成: ${_tasks.length} 个任务, ${_tags.length} 个标签');
    } catch (e) {
      debugPrint('自动备份失败: $e');
    }
  }

  /// 获取自动备份数据
  Map<String, dynamic>? getAutoBackup() {
    final backupJson = _prefs?.getString(_backupKey);
    if (backupJson != null) {
      return jsonDecode(backupJson) as Map<String, dynamic>;
    }
    return null;
  }

  /// 从备份数据恢复
  Future<bool> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      // 恢复标签
      if (backupData['tags'] != null) {
        final List<dynamic> tagsJson = backupData['tags'];
        _tags = tagsJson.map((json) => Tag.fromJson(json)).toList();
        await _saveTags();
      }

      // 恢复任务
      if (backupData['tasks'] != null) {
        final List<dynamic> tasksJson = backupData['tasks'];
        _tasks = tasksJson.map((json) => Task.fromJson(json)).toList();
        await _saveTasks();
      }

      debugPrint('从备份恢复完成: ${_tasks.length} 个任务, ${_tags.length} 个标签');
      return true;
    } catch (e) {
      debugPrint('从备份恢复失败: $e');
      return false;
    }
  }

  /// 清除自动备份数据
  Future<void> clearAutoBackup() async {
    try {
      await _prefs?.remove(_backupKey);
      debugPrint('自动备份数据已清除');
    } catch (e) {
      debugPrint('清除自动备份数据失败: $e');
    }
  }

  /// 获取导出数据（用于下载）
  String getExportData() {
    final exportData = {
      'version': '1.0',
      'exportTime': DateTime.now().toIso8601String(),
      'tasks': _tasks.map((t) => t.toJson()).toList(),
      'tags': _tags.map((t) => t.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// 获取任务数量
  int get taskCount => _tasks.length;

  /// 获取标签数量
  int get tagCount => _tags.length;
}

/// 全局存储服务实例（单例）
StorageService? _storageInstance;

/// 获取存储服务实例（单例模式）
StorageService getStorageService() {
  _storageInstance ??= kIsWeb
      ? WebStorageService()
      : createNativeStorageService();
  return _storageInstance!;
}

/// 重置存储服务单例（用于数据库连接重置）
void resetStorageService() {
  _storageInstance = null;
}
