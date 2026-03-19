import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../database/storage_service.dart';
import '../database/database_helper.dart';

// 条件导入：文件操作
import '../utils/platform_file_stub.dart'
    if (dart.library.html) '../utils/platform_file_web.dart'
    if (dart.library.io) '../utils/platform_file_native.dart';

/// 任务状态管理
class TaskProvider extends ChangeNotifier {
  final StorageService _storage = getStorageService();

  List<Task> _tasks = [];
  List<Task> _todayTasks = [];
  List<Task> _overdueTasks = [];
  List<Tag> _tags = [];
  bool _isLoading = false;
  String? _error;

  // 筛选条件
  TaskStatus? _filterStatus;
  TaskPriority? _filterPriority;
  String? _filterTagId;
  String _searchQuery = '';

  // Getters
  List<Task> get tasks => _tasks;
  List<Task> get todayTasks => _todayTasks;
  List<Task> get overdueTasks => _overdueTasks;
  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;
  String? get error => _error;
  TaskStatus? get filterStatus => _filterStatus;
  TaskPriority? get filterPriority => _filterPriority;
  String? get filterTagId => _filterTagId;
  String get searchQuery => _searchQuery;

  /// 筛选后的任务列表
  List<Task> get filteredTasks {
    var result = _tasks;

    if (_filterStatus != null) {
      result = result.where((t) => t.status == _filterStatus).toList();
    }

    if (_filterPriority != null) {
      result = result.where((t) => t.priority == _filterPriority).toList();
    }

    if (_filterTagId != null) {
      result = result.where((t) => t.tagIds.contains(_filterTagId)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result
          .where(
            (t) =>
                t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                (t.content?.toLowerCase().contains(
                          _searchQuery.toLowerCase(),
                        ) ??
                    false),
          )
          .toList();
    }

    return result;
  }

  /// 统计数据
  Map<String, int> get stats {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isCompleted).length;
    final pending = _tasks.where((t) => t.status == TaskStatus.pending).length;
    final inProgress =
        _tasks.where((t) => t.status == TaskStatus.inProgress).length;
    final overdue = _overdueTasks.length;

    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'inProgress': inProgress,
      'overdue': overdue,
    };
  }

  /// 初始化加载数据
  Future<void> loadData() async {
    debugPrint('===== TaskProvider.loadData 开始 =====');
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

      // 打印任务详情用于调试
      if (tasks.isEmpty) {
        debugPrint('⚠️ 警告：数据库中没有任务！');
      } else {
        debugPrint('前5个任务标题：');
        for (int i = 0; i < tasks.length && i < 5; i++) {
          debugPrint('  ${i + 1}. ${tasks[i].title} (状态: ${tasks[i].status})');
        }
      }

      debugPrint('正在从数据库加载标签...');
      var tags = await _storage.getAllTags();
      debugPrint('从数据库加载到 ${tags.length} 个标签');

      debugPrint('正在计算逾期任务...');
      final overdue = await _storage.getOverdueTasks();
      debugPrint('计算得到 ${overdue.length} 个逾期任务');

      debugPrint('===== 数据加载完成 =====');
      debugPrint('任务数量: ${tasks.length}');
      debugPrint('标签数量: ${tags.length}');
      debugPrint('逾期任务: ${overdue.length}');

      _tasks = tasks;

      // 初始化默认标签（如果不存在）
      tags = await _ensureDefaultTags(tags);

      _tags = tags;
      // 逾期任务：未完成、未取消且已过截止时间
      _overdueTasks = tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.status != TaskStatus.cancelled &&
                t.isOverdue,
          )
          .toList();

      // 今日任务：使用统一的计算方法
      _recalculateTodayTasks();

      debugPrint('待处理任务: ${_todayTasks.length}');
      debugPrint('内存中的任务列表长度: ${_tasks.length}');

      _isLoading = false;
      debugPrint('===== TaskProvider.loadData 完成 =====');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('===== TaskProvider.loadData 失败 =====');
      debugPrint('错误: $e');
      debugPrint('堆栈跟踪: $stackTrace');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow; // 重新抛出异常，让上层知道加载失败
    }
  }

  /// 确保默认标签存在
  Future<List<Tag>> _ensureDefaultTags(List<Tag> existingTags) async {
    final defaultTags = Tag.getDefaultTags();
    final List<Tag> resultTags = List.from(existingTags);
    bool needsAdd = false;

    for (final defaultTag in defaultTags) {
      // 检查是否已存在（通过ID或名称）
      final existsById = resultTags.any((t) => t.id == defaultTag.id);
      final existsByName = resultTags.any((t) => t.name == defaultTag.name);

      if (!existsById && !existsByName) {
        // 不存在，添加默认标签
        resultTags.add(defaultTag);
        needsAdd = true;
        debugPrint('添加默认标签: ${defaultTag.name}');
      }
    }

    // 如果需要添加标签，保存到存储
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

      // 直接添加到内存列表
      _tasks.insert(0, task);

      // 重新计算今日任务和逾期任务（使用统一的计算方法）
      _recalculateTodayTasks();
      _overdueTasks = _tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.status != TaskStatus.cancelled &&
                t.isOverdue,
          )
          .toList();

      debugPrint('任务列表长度: ${_tasks.length}');
      debugPrint('今日任务长度: ${_todayTasks.length}');

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
      // 检查是否是周期任务被标记为已完成
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

      // 重新计算今日任务和逾期任务
      _recalculateTodayTasks();
      // 逾期任务：未完成、未取消且已过截止时间
      _overdueTasks = _tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.status != TaskStatus.cancelled &&
                t.isOverdue,
          )
          .toList();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 创建周期任务的下一期任务
  Future<void> _createRecurringTask(Task completedTask) async {
    try {
      // 防止重复创建：检查是否已经为这个任务创建过周期任务
      // 通过检查是否有相同标题且刚创建的待处理任务
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

      // 基于原任务的截止时间计算新的截止时间
      // 如果原任务有截止时间，则基于该截止时间加上周期长度
      // 如果没有截止时间，则基于当前时间加上周期长度
      final baseTime = completedTask.dueTime ?? now;

      // 根据周期规则计算新的截止时间
      switch (completedTask.recurringRule) {
        case 'daily':
          newDueTime = baseTime.add(const Duration(days: 1));
          break;
        case 'weekly':
          newDueTime = baseTime.add(const Duration(days: 7));
          break;
        case 'monthly':
          // 加一个月，保持相同的日期和时间
          int newMonth = baseTime.month + 1;
          int newYear = baseTime.year;
          if (newMonth > 12) {
            newMonth = 1;
            newYear++;
          }
          // 处理月末日期问题（如1月31日 -> 2月28/29日）
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

      // 重新计算今日任务，确保新创建的周期任务能立即显示
      _recalculateTodayTasks();

      debugPrint(
        '周期任务已创建: ${newTask.title}, 原截止时间: ${completedTask.dueTime}, 新截止时间: $newDueTime',
      );
    } catch (e) {
      debugPrint('创建周期任务失败: $e');
    }
  }

  /// 重新计算今日任务列表
  /// 显示今天的所有任务（包括已完成和未完成）
  void _recalculateTodayTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    _todayTasks = _tasks.where((t) {
      // 包含今天创建的任务
      if (t.createdAt != null) {
        final createdDate = t.createdAt!;
        if (createdDate.year == now.year &&
            createdDate.month == now.month &&
            createdDate.day == now.day) {
          return true;
        }
      }
      // 包含今天截止的任务
      if (t.dueTime != null) {
        final due = t.dueTime!;
        if (due.isAfter(today) && due.isBefore(tomorrow)) {
          return true;
        }
      }
      // 包含所有未完成的任务（作为默认显示）
      if (!t.isCompleted) {
        return true;
      }
      return false;
    }).toList();
  }

  /// 删除任务
  Future<void> deleteTask(String id) async {
    try {
      await _storage.deleteTask(id);
      _tasks.removeWhere((t) => t.id == id);

      // 重新计算今日任务和逾期任务（使用统一的计算方法）
      _recalculateTodayTasks();
      _overdueTasks = _tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.status != TaskStatus.cancelled &&
                t.isOverdue,
          )
          .toList();

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
      // 从已完成改为其他状态时，清除完成时间
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
      debugPrint('标签颜色: ${tag.color}');
      debugPrint('是否默认: ${tag.isDefault}');

      // 先检查内存中是否已存在
      final existingById = _tags.any((t) => t.id == tag.id);
      final existingByName = _tags.any(
        (t) => t.name.toLowerCase() == tag.name.toLowerCase(),
      );

      if (existingById || existingByName) {
        debugPrint('标签已存在，跳过添加: ${tag.name}');
        return;
      }

      // 调用存储服务插入（存储服务也会检查重复）
      await _storage.insertTag(tag);
      debugPrint('标签已插入到存储服务');

      // 重新从存储服务获取所有标签，确保数据一致
      final storageTags = await _storage.getAllTags();
      debugPrint('从存储服务获取到 ${storageTags.length} 个标签');

      // 查找新添加的标签
      final newTag = storageTags.firstWhere(
        (t) => t.id == tag.id || t.name.toLowerCase() == tag.name.toLowerCase(),
        orElse: () => tag,
      );

      // 检查是否已经在内存中
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

  /// 清除所有数据（任务和标签）
  Future<void> clearAllData() async {
    try {
      debugPrint('===== 开始清除所有数据 =====');

      // 清除所有任务
      for (final task in List.from(_tasks)) {
        await _storage.deleteTask(task.id);
      }

      // 清除所有标签
      for (final tag in List.from(_tags)) {
        await _storage.deleteTag(tag.id);
      }

      // 清空内存中的数据
      _tasks = [];
      _todayTasks = [];
      _overdueTasks = [];
      _tags = [];

      // 如果是Web平台，清除自动备份数据
      if (_storage is WebStorageService) {
        await (_storage as WebStorageService).clearAutoBackup();
        debugPrint('自动备份数据已清除');
      }

      // 如果是移动端，清除导出的文件
      if (kIsWeb == false) {
        try {
          await clearExportFiles();
          debugPrint('导出文件已清除');
        } catch (e) {
          debugPrint('清除导出文件失败: $e');
        }
      }

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

      // 解析任务列表
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

      // 解析标签列表
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

      // 重新从数据库加载所有数据，确保数据一致性和正确的排序
      await loadData();

      // 确保UI更新
      debugPrint('导入后任务数量: ${_tasks.length}');
      debugPrint('导入后标签数量: ${_tags.length}');
      notifyListeners();

      debugPrint('导入数据流程完成');
    } catch (e) {
      debugPrint('导入数据失败: $e');
      rethrow;
    }
  }

  /// 重置数据库连接（用于应用重启或恢复时）
  Future<void> resetDatabaseConnection() async {
    debugPrint('===== TaskProvider.resetDatabaseConnection 开始 =====');
    try {
      // 如果是原生平台，重置数据库连接
      if (_storage is! WebStorageService) {
        // 导入DatabaseHelper
        final dbHelper = DatabaseHelper();
        await dbHelper.resetConnection();
        debugPrint('数据库连接已重置');

        // 重新初始化存储服务
        await _storage.init();
        debugPrint('存储服务已重新初始化');
      } else {
        debugPrint('Web平台，无需重置数据库连接');
      }
      debugPrint('===== TaskProvider.resetDatabaseConnection 完成 =====');
    } catch (e) {
      debugPrint('重置数据库连接失败: $e');
      rethrow;
    }
  }
}
