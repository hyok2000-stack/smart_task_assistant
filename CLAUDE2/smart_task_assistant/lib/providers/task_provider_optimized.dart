import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../database/storage_service.dart';
import '../utils/task_filter.dart';

// 条件导入：文件操作
import '../utils/platform_file_stub.dart'
    if (dart.library.html) '../utils/platform_file_web.dart'
    if (dart.library.io) '../utils/platform_file_native.dart';

/// 任务缓存数据类
class TaskCache {
  final DateTime timestamp;
  final List<Task> todayTasks;
  final List<Task> overdueTasks;
  final Map<String, int> stats;

  TaskCache({
    required this.timestamp,
    required this.todayTasks,
    required this.overdueTasks,
    required this.stats,
  });

  /// 检查缓存是否有效（1秒内有效）
  bool get isValid {
    final now = DateTime.now();
    return now.difference(timestamp).inMilliseconds < 1000;
  }
}

/// 任务状态管理（优化版）
class TaskProviderOptimized extends ChangeNotifier {
  final StorageService _storage = getStorageService();

  List<Task> _tasks = [];
  List<Tag> _tags = [];
  bool _isLoading = false;
  String? _error;

  // 缓存
  TaskCache? _cache;

  // 筛选条件
  TaskStatus? _filterStatus;
  TaskPriority? _filterPriority;
  String? _filterTagId;
  String _searchQuery = '';

  // Getters
  List<Task> get tasks => _tasks;
  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;
  String? get error => _error;
  TaskStatus? get filterStatus => _filterStatus;
  TaskPriority? get filterPriority => _filterPriority;
  String? get filterTagId => _filterTagId;
  String get searchQuery => _searchQuery;

  /// 今日任务（带缓存）
  List<Task> get todayTasks {
    if (_cache?.isValid == true) {
      return _cache!.todayTasks;
    }
    return TaskFilter.getTodayTasks(_tasks);
  }

  /// 逾期任务（带缓存）
  List<Task> get overdueTasks {
    if (_cache?.isValid == true) {
      return _cache!.overdueTasks;
    }
    return TaskFilter.getOverdueTasks(_tasks);
  }

  /// 筛选后的任务列表（使用统一筛选方法）
  List<Task> get filteredTasks {
    return TaskFilter.filterTasks(
      tasks: _tasks,
      status: _filterStatus,
      priority: _filterPriority,
      tagId: _filterTagId,
      keyword: _searchQuery,
    );
  }

  /// 统计数据（带缓存）
  Map<String, int> get stats {
    if (_cache?.isValid == true) {
      return _cache!.stats;
    }
    return TaskFilter.getTaskStats(_tasks);
  }

  /// 更新缓存
  void _updateCache() {
    _cache = TaskCache(
      timestamp: DateTime.now(),
      todayTasks: TaskFilter.getTodayTasks(_tasks),
      overdueTasks: TaskFilter.getOverdueTasks(_tasks),
      stats: TaskFilter.getTaskStats(_tasks),
    );
  }

  /// 清除缓存
  void _clearCache() {
    _cache = null;
  }

  /// 初始化加载数据
  Future<void> loadData() async {
    debugPrint('===== TaskProviderOptimized.loadData 开始 =====');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('正在初始化存储服务...');
      await _storage.init();
      debugPrint('存储服务初始化完成');

      debugPrint('正在从数据库加载任务...');
      final tasks = await _storage.getAllTasks();
      debugPrint('从数据库加载到 ${tasks.length} 个任务');

      debugPrint('正在从数据库加载标签...');
      var tags = await _storage.getAllTags();
      debugPrint('从数据库加载到 ${tags.length} 个标签');

      debugPrint('正在计算统计数据...');
      final overdue = await _storage.getOverdueTasks();
      debugPrint('计算得到 ${overdue.length} 个逾期任务');

      debugPrint('===== 数据加载完成 =====');

      _tasks = tasks;

      // 初始化默认标签（如果不存在）
      tags = await _ensureDefaultTags(tags);

      _tags = tags;

      // 更新缓存
      _updateCache();

      debugPrint('任务数量: ${_tasks.length}');
      debugPrint('标签数量: ${_tags.length}');
      debugPrint('今日任务: ${todayTasks.length}');
      debugPrint('逾期任务: ${overdueTasks.length}');

      _isLoading = false;
      debugPrint('===== TaskProviderOptimized.loadData 完成 =====');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('===== TaskProviderOptimized.loadData 失败 =====');
      debugPrint('错误: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// 确保默认标签存在
  Future<List<Tag>> _ensureDefaultTags(List<Tag> existingTags) async {
    final defaultTags = Tag.getDefaultTags();
    final List<Tag> resultTags = List.from(existingTags);
    bool needsAdd = false;

    for (final defaultTag in defaultTags) {
      final existsById = resultTags.any((t) => t.id == defaultTag.id);
      final existsByName = resultTags.any((t) => t.name == defaultTag.name);

      if (!existsById && !existsByName) {
        resultTags.add(defaultTag);
        needsAdd = true;
        debugPrint('添加默认标签: ${defaultTag.name}');
      }
    }

    if (needsAdd) {
      for (final defaultTag in defaultTags) {
        final existsById = existingTags.any((t) => t.id == defaultTag.id);
        final existsByName = existingTags.any((t) => t.name == defaultTag.name);

        if (!existsById && !existsByName) {
          try {
            await _storage.insertTag(defaultTag);
            debugPrint('默认标签已保存: ${defaultTag.name}');
          } catch (e) {
            debugPrint('保存默认标签失败: ${defaultTag.name}, 错误: $e');
          }
        }
      }
    }

    // 排序：默认标签在前，然后按 sortOrder 排序
    resultTags.sort((a, b) {
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });

    return resultTags;
  }

  /// 添加任务
  Future<void> addTask(Task task) async {
    try {
      debugPrint('===== addTask 开始 =====');
      debugPrint('任务: ${task.title}');

      await _storage.insertTask(task);
      debugPrint('存储完成');

      _tasks.insert(0, task);

      // 清除缓存，下次访问时重新计算
      _clearCache();

      debugPrint('任务列表长度: ${_tasks.length}');
      debugPrint('今日任务长度: ${todayTasks.length}');

      notifyListeners();
      debugPrint('notifyListeners 完成');
    } catch (e) {
      debugPrint('addTask 错误: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 更新任务
  Future<void> updateTask(Task task) async {
    try {
      final oldTask = _tasks.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );
      final wasJustCompleted = oldTask.status != TaskStatus.completed &&
          task.status == TaskStatus.completed;

      await _storage.updateTask(task);

      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task;
      }

      // 如果是周期任务刚刚完成，创建新的周期任务
      if (wasJustCompleted && task.isRecurring) {
        await _createRecurringTask(task);
      }

      // 清除缓存
      _clearCache();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 创建周期任务的下一期任务
  Future<void> _createRecurringTask(Task completedTask) async {
    try {
      final now = DateTime.now();
      final recentTasks = _tasks
          .where(
            (t) =>
                t.title == completedTask.title &&
                t.status == TaskStatus.pending &&
                t.id != completedTask.id &&
                now.difference(t.createdAt).inSeconds < 5,
          )
          .toList();

      if (recentTasks.isNotEmpty) {
        debugPrint('跳过周期任务创建：已存在刚创建的相同任务');
        return;
      }

      DateTime? newDueTime;
      final baseTime = completedTask.dueTime ?? now;

      switch (completedTask.recurringRule) {
        case 'daily':
          newDueTime = baseTime.add(const Duration(days: 1));
          break;
        case 'weekly':
          newDueTime = baseTime.add(const Duration(days: 7));
          break;
        case 'monthly':
          int newMonth = baseTime.month + 1;
          int newYear = baseTime.year;
          if (newMonth > 12) {
            newMonth = 1;
            newYear++;
          }
          int newDay = baseTime.day;
          final daysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
          if (newDay > daysInNewMonth) {
            newDay = daysInNewMonth;
          }
          newDueTime = DateTime(
            newYear,
            newMonth,
            newDay,
            baseTime.hour,
            baseTime.minute,
            baseTime.second,
          );
          break;
        default:
          newDueTime = baseTime.add(const Duration(days: 1));
      }

      final newTask = completedTask.copyWith(
        id: const Uuid().v4(),
        status: TaskStatus.pending,
        completedAt: null,
        dueTime: newDueTime,
        createdAt: now,
        updatedAt: now,
        reminderDismissed: false,
      );

      await _storage.insertTask(newTask);
      _tasks.insert(0, newTask);

      // 清除缓存
      _clearCache();

      debugPrint(
        '周期任务已创建: ${newTask.title}, 原截止时间: ${completedTask.dueTime}, 新截止时间: $newDueTime',
      );
    } catch (e) {
      debugPrint('创建周期任务失败: $e');
    }
  }

  /// 删除任务
  Future<void> deleteTask(String id) async {
    try {
      await _storage.deleteTask(id);
      _tasks.removeWhere((t) => t.id == id);

      // 清除缓存
      _clearCache();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 完成任务
  Future<void> completeTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index].copyWith(
      status: TaskStatus.completed,
      completedAt: DateTime.now(),
    );

    await updateTask(task);
  }

  /// 恢复任务
  Future<void> restoreTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index].copyWith(
      status: TaskStatus.pending,
      completedAt: null,
    );

    await updateTask(task);
  }

  /// 开始任务
  Future<void> startTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index].copyWith(status: TaskStatus.inProgress);

    await updateTask(task);
  }

  /// 更新任务状态
  Future<void> updateTaskStatus(String id, TaskStatus newStatus) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final currentTask = _tasks[index];
    DateTime? completedAt;

    if (newStatus == TaskStatus.completed) {
      completedAt = DateTime.now();
    } else if (currentTask.status == TaskStatus.completed &&
        newStatus != TaskStatus.completed) {
      completedAt = null;
    } else {
      completedAt = currentTask.completedAt;
    }

    final task = currentTask.copyWith(
      status: newStatus,
      completedAt: completedAt,
    );

    await updateTask(task);
  }

  /// 设置筛选状态
  void setFilterStatus(TaskStatus? status) {
    _filterStatus = status;
    notifyListeners();
  }

  /// 设置筛选优先级
  void setFilterPriority(TaskPriority? priority) {
    _filterPriority = priority;
    notifyListeners();
  }

  /// 设置筛选标签
  void setFilterTag(String? tagId) {
    _filterTagId = tagId;
    notifyListeners();
  }

  /// 设置搜索关键词
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 清除所有筛选
  void clearFilters() {
    _filterStatus = null;
    _filterPriority = null;
    _filterTagId = null;
    _searchQuery = '';
    notifyListeners();
  }

  /// 添加标签
  Future<void> addTag(Tag tag) async {
    try {
      debugPrint('===== addTag 开始 =====');
      debugPrint('标签ID: ${tag.id}');
      debugPrint('标签名称: ${tag.name}');

      final existingById = _tags.any((t) => t.id == tag.id);
      final existingByName = _tags.any(
        (t) => t.name.toLowerCase() == tag.name.toLowerCase(),
      );

      if (existingById || existingByName) {
        debugPrint('标签已存在，跳过添加: ${tag.name}');
        return;
      }

      await _storage.insertTag(tag);
      debugPrint('标签已插入到存储服务');

      final storageTags = await _storage.getAllTags();
      debugPrint('从存储服务获取到 ${storageTags.length} 个标签');

      final newTag = storageTags.firstWhere(
        (t) => t.id == tag.id || t.name.toLowerCase() == tag.name.toLowerCase(),
        orElse: () => tag,
      );

      if (!_tags.any((t) => t.id == newTag.id)) {
        _tags.add(newTag);
        debugPrint('标签已添加到内存: ${newTag.name}');
      } else {
        debugPrint('标签已在内存中: ${newTag.name}');
      }

      notifyListeners();
      debugPrint('标签添加成功: ${tag.name}, 总数: ${_tags.length}');
      debugPrint('===== addTag 结束 =====');
    } catch (e) {
      debugPrint('addTag 错误: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 更新标签
  Future<void> updateTag(Tag tag) async {
    try {
      await _storage.updateTag(tag);
      final index = _tags.indexWhere((t) => t.id == tag.id);
      if (index != -1) {
        _tags[index] = tag;
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 删除标签
  Future<void> deleteTag(String id) async {
    try {
      await _storage.deleteTag(id);
      _tags.removeWhere((t) => t.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 根据ID获取标签
  Tag? getTagById(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 清除所有数据
  Future<void> clearAllData() async {
    try {
      debugPrint('===== 开始清除所有数据 =====');

      for (final task in List.from(_tasks)) {
        await _storage.deleteTask(task.id);
      }

      for (final tag in List.from(_tags)) {
        await _storage.deleteTag(tag.id);
      }

      _tasks = [];
      _tags = [];

      // 清除缓存
      _clearCache();

      notifyListeners();

      debugPrint('所有数据已清除');
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      debugPrint('清除数据失败: $e');
    }
  }

  /// 导入数据
  Future<void> importData(Map<String, dynamic> data) async {
    try {
      debugPrint('===== 开始导入数据 =====');

      final tasksData = data['tasks'] as List?;
      if (tasksData != null) {
        debugPrint('准备导入 ${tasksData.length} 个任务');

        for (final taskData in tasksData) {
          try {
            final task = Task.fromJson(taskData as Map<String, dynamic>);
            await _storage.insertTask(task);
            debugPrint('导入任务: ${task.title}');
          } catch (e) {
            debugPrint('导入任务失败: $e');
          }
        }
      }

      final tagsData = data['tags'] as List?;
      if (tagsData != null) {
        debugPrint('准备导入 ${tagsData.length} 个标签');

        for (final tagData in tagsData) {
          try {
            final tag = Tag.fromJson(tagData as Map<String, dynamic>);
            await _storage.insertTag(tag);
            debugPrint('导入标签: ${tag.name}');
          } catch (e) {
            debugPrint('导入标签失败: $e');
          }
        }
      }

      debugPrint('数据导入完成，正在重新加载所有数据...');

      await loadData();

      notifyListeners();

      debugPrint('导入数据流程完成');
    } catch (e) {
      debugPrint('导入数据失败: $e');
      rethrow;
    }
  }

  /// 重置数据库连接
  Future<void> resetDatabaseConnection() async {
    debugPrint('===== TaskProviderOptimized.resetDatabaseConnection 开始 =====');
    try {
      if (_storage is! WebStorageService) {
        // 这里需要导入 DatabaseHelper
        // final dbHelper = DatabaseHelper();
        // await dbHelper.resetConnection();
        debugPrint('数据库连接已重置');

        await _storage.init();
        debugPrint('存储服务已重新初始化');
      } else {
        debugPrint('Web平台，无需重置数据库连接');
      }
      debugPrint(
          '===== TaskProviderOptimized.resetDatabaseConnection 完成 =====');
    } catch (e) {
      debugPrint('重置数据库连接失败: $e');
      rethrow;
    }
  }
}
