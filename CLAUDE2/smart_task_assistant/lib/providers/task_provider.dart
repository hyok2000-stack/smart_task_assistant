import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../models/sync_queue_item.dart';
import '../models/tag.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../database/storage_service.dart';
import '../database/database_helper.dart';
import '../services/backend_api_service.dart';
import '../services/sync_queue_service.dart';
import '../services/task_comment_service.dart';
import '../services/task_history_service.dart';

// 条件导入：文件操作
import '../utils/platform_file_stub.dart'
    if (dart.library.html) '../utils/platform_file_web.dart'
    if (dart.library.io) '../utils/platform_file_native.dart';

/// 任务状态管理
class TaskProvider extends ChangeNotifier {
  StorageService _storage = getStorageService();

  // 提醒状态清除回调
  Function(String taskId)? onReminderReset;
  bool autoCompleteParentTasks = true;

  // Native reminder data change notification
  static const _reminderChannel =
      MethodChannel('com.smarttask.smart_task_assistant/reminder');

  void _notifyNativeDataChanged(String type, [String? id]) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // invokeMethod 返回 Future，真正的 PlatformException 是异步到达的，
    // 同步 try/catch 无法捕获——必须用 catchError，否则在 release 模式下
    // 会触发原生崩溃。
    _reminderChannel.invokeMethod(
        'notifyDataChanged', {'type': type, 'id': id}).catchError((_) {});
  }

  List<Task> _tasks = [];
  List<Task> _archivedTasks = [];
  List<Task> _todayTasks = [];
  List<Task> _overdueTasks = [];
  List<Tag> _tags = [];
  bool _isLoading = false;
  String? _error;
  bool _isBackendSyncing = false;
  bool _isSyncRunning = false;
  bool _suppressNotify = false;
  // 自动备份节流：上次备份时间，5 分钟内不重复备份
  DateTime? _lastAutoBackupAt;
  static const _autoBackupThrottle = Duration(minutes: 5);
  // 最近一次删除的任务（供 UI 层"撤销删除"恢复）
  // 最近删除的任务（供 UI 层"撤销删除"恢复），按 id 存储，支持多个
  final Map<String, Task> _recentlyDeletedTasks = {};
  DateTime? _lastBackendSyncAt;
  String? _backendSyncError;
  int _pendingBackendSyncCount = 0;
  Set<String> _distributedTaskIds = {};
  List<BackendDistribution> _distributions = [];
  List<ConflictInfo> _conflicts = [];

  // 缓存的筛选列表
  List<Task> _cachedCompletedTasks = [];
  List<Task> _cachedActiveTasks = [];
  // filteredTasks 的惰性缓存：在 _tasks 或筛选条件变更时失效。
  // 避免在 build 中多次访问 filteredTasks getter 时重复计算（每次都
  // 串联多个 where().toList()）。约定：调用方不应就地修改返回的 List。
  List<Task>? _filteredTasksCache;
  final BackendApiService _backend = BackendApiService.instance;

  // 筛选条件
  TaskStatus? _filterStatus;
  TaskPriority? _filterPriority;
  String? _filterTagId;
  String _searchQuery = '';
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  List<String> _recentSearches = [];

  // Getters
  List<Task> get tasks => _tasks;
  List<Task> get archivedTasks => List.unmodifiable(_archivedTasks);
  List<Task> get todayTasks => _todayTasks;
  List<Task> get overdueTasks => _overdueTasks;
  List<Task> get completedTasks => _cachedCompletedTasks;
  List<Task> get activeTasks => _cachedActiveTasks;
  List<Tag> get tags => _tags;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isBackendSyncing => _isBackendSyncing;
  DateTime? get lastBackendSyncAt => _lastBackendSyncAt;
  String? get backendSyncError => _backendSyncError;
  int get pendingBackendSyncCount => _pendingBackendSyncCount;
  bool get isBackendLoggedIn => _backend.isLoggedIn;
  Set<String> get distributedTaskIds => _distributedTaskIds;
  List<BackendDistribution> get distributions => _distributions;
  List<SyncQueueItem> get syncQueue => SyncQueueService.instance.items;
  List<ConflictInfo> get conflicts => _conflicts;
  bool get hasConflicts => _conflicts.isNotEmpty;
  TaskStatus? get filterStatus => _filterStatus;
  TaskPriority? get filterPriority => _filterPriority;
  String? get filterTagId => _filterTagId;
  String get searchQuery => _searchQuery;

  /// 筛选后的任务列表
  List<Task> get filteredTasks {
    // 惰性缓存：命中则直接返回，避免 build 中重复计算
    final cached = _filteredTasksCache;
    if (cached != null) return cached;

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
      final q = _searchQuery.toLowerCase();
      // 预构建 tagId -> tagName 映射，支持按标签名搜索
      final tagNameById = {
        for (final tag in _tags) tag.id: tag.name.toLowerCase(),
      };
      result = result
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              (t.content?.toLowerCase().contains(q) ?? false) ||
              (t.assignee?.toLowerCase().contains(q) ?? false) ||
              // 按标签名匹配
              t.tagIds.any((id) => (tagNameById[id] ?? '').contains(q)))
          .toList();
    }

    if (_filterDateFrom != null || _filterDateTo != null) {
      result = result.where((t) {
        final dt = t.dueTime ?? t.startTime;
        if (dt == null) return false;
        if (_filterDateFrom != null && dt.isBefore(_filterDateFrom!)) {
          return false;
        }
        if (_filterDateTo != null &&
            dt.isAfter(_filterDateTo!.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      }).toList();
    }

    _filteredTasksCache = result;
    return result;
  }

  /// 排序后的任务列表（置顶在前，然后按 sortOrder，再按 createdAt）
  List<Task> get sortedTasks {
    return List.of(_tasks)
      ..sort((a, b) {
        final aOrder = a.sortOrder ?? 0;
        final bOrder = b.sortOrder ?? 0;
        if (aOrder < 0 && bOrder >= 0) return -1;
        if (bOrder < 0 && aOrder >= 0) return 1;
        final orderCmp = aOrder.compareTo(bOrder);
        if (orderCmp != 0) return orderCmp;
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  bool isPinned(String taskId) {
    final t = _tasks.where((t) => t.id == taskId);
    return t.isNotEmpty && (t.first.sortOrder ?? 0) < 0;
  }

  Future<void> pinTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _tasks[index] = _tasks[index].copyWith(sortOrder: -1);
    await _storage.updateTask(_tasks[index]);
    _syncTaskSilently(_tasks[index]);
    _refreshTaskLists();
    notifyListeners();
  }

  Future<void> unpinTask(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _tasks[index] = _tasks[index].copyWith(sortOrder: 0);
    await _storage.updateTask(_tasks[index]);
    _syncTaskSilently(_tasks[index]);
    _refreshTaskLists();
    notifyListeners();
  }

  Future<void> reorderTasks(int oldIndex, int newIndex,
      {List<Task>? displayTasks}) async {
    if (oldIndex == newIndex) return;
    final source = displayTasks ?? _tasks;
    final list = List.of(source);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    int nonPinnedIndex = 0;
    for (int i = 0; i < list.length; i++) {
      final isPinned = (list[i].sortOrder ?? 0) < 0;
      final order = isPinned ? list[i].sortOrder : nonPinnedIndex++;
      final idx = _tasks.indexWhere((t) => t.id == list[i].id);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(sortOrder: order);
        await _storage.updateTask(_tasks[idx]);
      }
    }
    notifyListeners();
  }

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

      debugPrint('===== 数据加载完成 =====');
      debugPrint('任务数量: ${tasks.length}');
      debugPrint('标签数量: ${tags.length}');

      _archivedTasks = tasks.where((t) => t.archivedAt != null).toList();
      _tasks = tasks.where((t) => t.archivedAt == null).toList();
      // 全量重载后，filteredTasks 缓存失效
      _filteredTasksCache = null;

      // 初始化默认标签（如果不存在）
      tags = await _ensureDefaultTags(tags);

      _tags = tags;
      // 逾期任务：未完成、未取消且已过截止时间（基于已加载的 tasks 在内存计算，
      // 不再单独查询数据库——避免与内存视图不一致）
      // 逾期列表只能来自活动任务。此前使用包含归档任务的 tasks，导致归档中的
      // 逾期任务仍出现在首页，但完成操作无法在 _tasks 中找到它，从而点击无反应。
      _overdueTasks = _tasks
          .where(
            (t) =>
                !t.isCompleted &&
                t.status != TaskStatus.cancelled &&
                t.isOverdue,
          )
          .toList();

      // 今日任务：使用统一的计算方法
      _recalculateTodayTasks();

      // 初始化缓存列表
      _cachedCompletedTasks = _tasks.where((t) => t.isCompleted).toList();
      _cachedActiveTasks = _tasks
          .where((t) => !t.isCompleted && t.status != TaskStatus.cancelled)
          .toList();

      debugPrint('待处理任务: ${_todayTasks.length}');
      debugPrint('内存中的任务列表长度: ${_tasks.length}');

      _isLoading = false;
      debugPrint('===== TaskProvider.loadData 完成 =====');
      await _backend.init();
      _lastBackendSyncAt = await _backend.getLastSyncAt();
      await _loadBackendSyncState();
      notifyListeners();

      // 任务数据整体变化（含后端同步 pull 直写库的场景）→
      // 通知原生刷新桌面小组件；原生服务未启动时静默失败（onResume 会补刷）
      _notifyNativeDataChanged('all', null);
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
      try {
        await TaskHistoryService.instance.recordTaskCreated(task);
      } catch (historyError) {
        debugPrint('任务已创建，但创建审计记录失败: $historyError');
      }
      debugPrint('存储完成');

      // 直接添加到内存列表
      _tasks.insert(0, task);

      // 重新计算今日任务和逾期任务（使用统一的计算方法）
      _refreshTaskLists();

      debugPrint('任务列表长度: ${_tasks.length}');
      debugPrint('今日任务长度: ${_todayTasks.length}');

      notifyListeners();
      debugPrint('notifyListeners 完成');
      _notifyNativeDataChanged('task', task.id);
      _syncTaskSilently(task);
    } catch (e) {
      debugPrint('addTask 错误: $e');
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 更新任务
  Future<void> updateTask(Task task) async {
    try {
      // 本地编辑递增 version，使云端冲突检测（clientVersion vs serverVersion）生效
      task = task.copyWith(
        version: (task.version ?? 1) + 1,
        updatedAt: DateTime.now(),
      );
      // 从内存列表获取旧任务（避免全表数据库查询）
      final taskIndex = _tasks.indexWhere((t) => t.id == task.id);
      final oldTask = taskIndex >= 0 ? _tasks[taskIndex] : task;

      // 检查是否是周期任务被标记为已完成
      final wasJustCompleted = oldTask.status != TaskStatus.completed &&
          task.status == TaskStatus.completed;

      // 检查提醒相关字段是否改变
      final reminderFieldsChanged = oldTask.dueTime != task.dueTime ||
          oldTask.reminderMinutes != task.reminderMinutes ||
          oldTask.reminderDismissed != task.reminderDismissed;

      // 写入数据库
      await _storage.updateTask(task);
      // 审计记录是辅助数据，不能让它的存储故障阻断任务本身的保存。
      try {
        await TaskHistoryService.instance.recordTaskChanges(oldTask, task);
      } catch (historyError) {
        debugPrint('任务已保存，但审计记录写入失败: $historyError');
      }

      // 内存中直接替换，避免全表 reload
      if (taskIndex >= 0) {
        _tasks[taskIndex] = task;
      }

      // 如果提醒字段改变了，通知提醒服务重置状态
      if (reminderFieldsChanged && onReminderReset != null) {
        onReminderReset!(task.id);
      }

      // 如果是周期任务刚刚完成，创建新的周期任务
      if (wasJustCompleted && task.isRecurring) {
        await _createRecurringTask(task);
      }

      // 子任务→父任务联动：子任务刚完成时，若父任务的所有子任务都已完成，
      // 则自动完成父任务（避免用户手动再点一次）。
      if (autoCompleteParentTasks &&
          wasJustCompleted &&
          task.parentId != null) {
        await _maybeCompleteParentTask(task.parentId!);
      }

      // 重新计算今日任务和逾期任务
      _refreshTaskLists();

      notifyListeners();
      _notifyNativeDataChanged('task', task.id);
      _syncTaskSilently(task);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 检查并自动完成父任务（当所有子任务都已完成时）。
  ///
  /// 子任务父子联动：用户逐个完成子任务后，最后一个完成时自动把父任务
  /// 也标记为已完成，避免用户还要手动再点一次父任务（与主流待办应用一致）。
  /// 仅当父任务存在、未取消、且有子任务时才触发。
  Future<void> _maybeCompleteParentTask(String parentId) async {
    try {
      final parentIndex = _tasks.indexWhere((t) => t.id == parentId);
      if (parentIndex == -1) return;
      final parent = _tasks[parentIndex];

      // 父任务已完成或已取消，无需联动
      if (parent.isCompleted || parent.status == TaskStatus.cancelled) return;

      final subtasks = _tasks.where((t) => t.parentId == parentId).toList();
      if (subtasks.isEmpty) return; // 无子任务不触发

      final allCompleted = subtasks.every((t) => t.isCompleted);
      if (!allCompleted) return;

      debugPrint('子任务全部完成，自动完成父任务: ${parent.title}');
      final updatedParent = parent.copyWith(
        status: TaskStatus.completed,
        completedAt: DateTime.now(),
      );
      await _storage.updateTask(updatedParent);
      _tasks[parentIndex] = updatedParent;
    } catch (e) {
      debugPrint('自动完成父任务失败: $e');
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

      // 锚定时间：基于原任务截止时间（保持"日/月"语义，避免月末任务逐期漂移）；
      // 原任务无截止时间时用当前时间。
      final anchor = completedTask.dueTime ?? now;
      final rule = completedTask.recurringRule;

      int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

      // 单次推进一个周期：月/年基于 t 递增，"日"基于 anchor 固定语义
      DateTime advance(DateTime t) {
        switch (rule) {
          case 'daily':
            return t.add(const Duration(days: 1));
          case 'weekly':
            return t.add(const Duration(days: 7));
          case 'monthly':
            // 月末任务（如 29/30/31 日）始终落在下一月的月末，
            // 避免逐期漂移到固定日期（如 31→28→28 而非 31→28→31）。
            final wasMonthEnd =
                anchor.day == daysInMonth(anchor.year, anchor.month);
            var nm = t.month + 1;
            var ny = t.year;
            if (nm > 12) {
              nm = 1;
              ny++;
            }
            final maxDay = daysInMonth(ny, nm);
            final day = wasMonthEnd
                ? maxDay
                : (anchor.day > maxDay ? maxDay : anchor.day);
            return DateTime(ny, nm, day, t.hour, t.minute, t.second);
          case 'yearly':
            final ny = t.year + 1;
            var day = anchor.day;
            // 闰年处理：Feb 29 在非闰年落到 Feb 28
            if (anchor.month == 2 &&
                anchor.day == 29 &&
                daysInMonth(ny, 2) != 29) {
              day = 28;
            }
            return DateTime(ny, anchor.month, day, t.hour, t.minute, t.second);
          default:
            return t.add(const Duration(days: 1));
        }
      }

      // 先推进一期；若仍落在过去（逾期才完成），则继续推进到未来，
      // 保持周期对齐（不补建错过的周期，例如"每周一"任务仍落在周一）。
      var newDueTime = advance(anchor);
      var guard = 0;
      while (newDueTime.isBefore(now) && guard < 10000) {
        newDueTime = advance(newDueTime);
        guard++;
      }

      final newTask = completedTask.copyWith(
        id: const Uuid().v4(),
        status: TaskStatus.pending,
        completedAt: null,
        dueTime: newDueTime,
        createdAt: now,
        updatedAt: now,
        reminderDismissed: false,
        version: 1, // 新任务（下一期）重置 version，不继承已完成任务的自增 version
      );

      await _storage.insertTask(newTask);
      _tasks.insert(0, newTask);
      _syncTaskSilently(newTask);

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
  /// 显示：今天创建的 + 今天截止的 + 今天完成的 + 逾期未完成的
  void _recalculateTodayTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    _todayTasks = _tasks.where((t) {
      // 包含今天完成的任务
      if (t.completedAt != null) {
        final completedDate = t.completedAt!;
        if (completedDate.year == now.year &&
            completedDate.month == now.month &&
            completedDate.day == now.day) {
          return true;
        }
      }

      // 包含今天创建的任务
      final createdDate = t.createdAt;
      if (createdDate.year == now.year &&
          createdDate.month == now.month &&
          createdDate.day == now.day) {
        return true;
      }
    
      // 包含今天截止的任务
      if (t.dueTime != null) {
        final due = t.dueTime!;
        if (!due.isBefore(today) && due.isBefore(tomorrow)) {
          return true;
        }
      }

      // 包含逾期未完成的任务
      if (!t.isCompleted && t.dueTime != null && t.dueTime!.isBefore(today)) {
        return true;
      }

      return false;
    }).toList();
  }

  /// 统一刷新任务列表（今日任务、逾期任务、缓存筛选列表）
  void _refreshTaskLists() {
    _recalculateTodayTasks();
    _overdueTasks = _tasks
        .where(
          (t) =>
              !t.isCompleted && t.status != TaskStatus.cancelled && t.isOverdue,
        )
        .toList();
    _cachedCompletedTasks = _tasks.where((t) => t.isCompleted).toList();
    _cachedActiveTasks = _tasks
        .where((t) => !t.isCompleted && t.status != TaskStatus.cancelled)
        .toList();
    // _tasks 已变更，filteredTasks 缓存失效
    _filteredTasksCache = null;
  }

  /// 关闭任务提醒（由原生层 FullScreenActivity 触发）
  Future<void> dismissReminder(String taskId) async {
    try {
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex == -1) return;

      final task = _tasks[taskIndex];
      final updatedTask = task.copyWith(reminderDismissed: true);
      await _storage.updateTask(updatedTask);
      _tasks[taskIndex] = updatedTask;

      _refreshTaskLists();
      notifyListeners();
      _notifyNativeDataChanged('task', taskId);
      debugPrint('Task reminder dismissed: $taskId');
    } catch (e) {
      debugPrint('Failed to dismiss reminder: $e');
    }
  }

  /// 触发自动备份（节流：5 分钟内只备份一次）。
  /// 返回 true 表示备份成功（或节流跳过视为成功），false 表示备份失败。
  Future<bool> _triggerAutoBackup() async {
    try {
      final now = DateTime.now();
      if (_lastAutoBackupAt != null &&
          now.difference(_lastAutoBackupAt!) < _autoBackupThrottle) {
        return true; // 节流窗口内，跳过
      }
      _lastAutoBackupAt = now;
      await _storage.autoBackup();
      return true;
    } catch (e) {
      debugPrint('触发自动备份失败: $e');
      return false;
    }
  }

  /// 从回收站恢复任务（重新加载列表使恢复的任务可见，
  /// 并回同步后端——撤销此前删除推送的墓碑，避免恢复被云端覆盖）
  Future<bool> restoreFromTrash(String trashId) async {
    try {
      final restored = await DatabaseHelper().restoreFromTrash(trashId);
      if (restored != null) {
        await loadData();
        await _syncTaskSilently(restored);
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 彻底删除回收站中的单条快照
  Future<void> purgeTrashItem(String trashId) async {
    try {
      await DatabaseHelper().purgeTrashItem(trashId);
    } catch (e) {
      debugPrint('彻底删除回收站快照失败: $e');
    }
  }

  /// 清空回收站
  Future<void> emptyTrash() async {
    try {
      await DatabaseHelper().emptyTrash();
    } catch (e) {
      debugPrint('清空回收站失败: $e');
    }
  }

  /// 删除任务
  Future<void> deleteTask(String id) async {
    try {
      // Save real task data before removing
      final realTask = _tasks.where((t) => t.id == id).firstOrNull;
      // 删除前缓存任务对象，供 UI 层"撤销删除"恢复（按 id 存储，支持多个）
      if (realTask != null) _recentlyDeletedTasks[id] = realTask;
      // 删除前触发一次自动备份（节流），作为数据安全兜底
      await _triggerAutoBackup();
      // 快照进回收站（30 天内可在回收站页面恢复）
      if (realTask != null) {
        try {
          await DatabaseHelper().moveToTrash(realTask);
        } catch (e) {
          debugPrint('移入回收站失败（已忽略，继续删除）: $e');
        }
      }
      await _storage.deleteTask(id);
      _tasks.removeWhere((t) => t.id == id);

      // 重新计算今日任务和逾期任务（使用统一的计算方法）
      _refreshTaskLists();

      notifyListeners();
      _notifyNativeDataChanged('task', id);
      final deletedTask = realTask ??
          Task(
            id: id,
            title: 'deleted',
            updatedAt: DateTime.now(),
          );
      _syncTaskSilently(deletedTask, deleted: true);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow; // 传播错误，让调用方知道删除失败
    }
  }

  Future<void> archiveTask(String id) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final archived = _tasks[index].copyWith(archivedAt: DateTime.now());
    await _storage.updateTask(archived);
    await TaskHistoryService.instance.record(
      taskId: id,
      action: '归档',
      field: '归档状态',
      beforeValue: '正常',
      afterValue: '已归档',
    );
    _tasks.removeAt(index);
    _archivedTasks.insert(0, archived);
    _refreshTaskLists();
    notifyListeners();
    _notifyNativeDataChanged('task', id);
    _syncTaskSilently(archived);
  }

  Future<void> restoreArchivedTask(String id) async {
    final index = _archivedTasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final restored = _archivedTasks[index].copyWith(archivedAt: null);
    await _storage.updateTask(restored);
    await TaskHistoryService.instance.record(
      taskId: id,
      action: '恢复',
      field: '归档状态',
      beforeValue: '已归档',
      afterValue: '正常',
    );
    _archivedTasks.removeAt(index);
    _tasks.insert(0, restored);
    _refreshTaskLists();
    notifyListeners();
    _notifyNativeDataChanged('task', id);
    _syncTaskSilently(restored);
  }

  Future<void> batchArchiveTasks(List<String> ids) async {
    for (final id in ids) {
      await archiveTask(id);
    }
  }

  Future<void> completeTaskWithSubtasks(
    String id, {
    required bool includeSubtasks,
  }) async {
    if (includeSubtasks) {
      final children = _tasks
          .where((task) => task.parentId == id && !task.isCompleted)
          .toList();
      for (final child in children) {
        await completeTask(child.id);
      }
    }
    await completeTask(id);
  }

  Future<void> archiveTaskWithSubtasks(
    String id, {
    required bool includeSubtasks,
  }) async {
    if (includeSubtasks) {
      final childIds = _tasks
          .where((task) => task.parentId == id)
          .map((task) => task.id)
          .toList();
      for (final childId in childIds) {
        await archiveTask(childId);
      }
    }
    await archiveTask(id);
  }

  Future<void> permanentlyDeleteArchivedTask(String id) async {
    final index = _archivedTasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final removed = _archivedTasks[index];
    await _storage.deleteTask(id);
    _archivedTasks.removeAt(index);
    await _cleanupUnreferencedAttachments(removed.attachmentPaths);
    notifyListeners();
    _notifyNativeDataChanged('task', id);
    _syncTaskSilently(removed, deleted: true);
  }

  Future<void> cleanupUnreferencedAttachments(Iterable<String> paths) async {
    await _cleanupUnreferencedAttachments(paths);
  }

  Future<void> _cleanupUnreferencedAttachments(Iterable<String> paths) async {
    final referenced = <String>{
      for (final task in [..._tasks, ..._archivedTasks])
        ...task.attachmentPaths,
    };
    for (final path in paths.toSet().difference(referenced)) {
      if (path.startsWith('content://')) continue;
      try {
        final normalized = path.replaceAll('\\', '/').toLowerCase();
        if (!normalized.contains('/attachments/')) continue;
        await deleteFile(path);
      } catch (e) {
        debugPrint('清理无引用附件失败: $path, $e');
      }
    }
  }

  /// 撤销最近一次删除（由 UI 层 SnackBar 的"撤销"按钮触发）。
  /// 恢复指定 id 的已删除任务（按 id 从缓存取出，而非只恢复最后一个）。
  /// 将缓存的任务重新插回 DB 和内存列表。返回是否恢复成功。
  Future<bool> undoDeleteTask(String id) async {
    final task = _recentlyDeletedTasks.remove(id);
    if (task == null) return false;
    try {
      await _storage.insertTask(task);
      _tasks.insert(0, task);
      _refreshTaskLists();
      notifyListeners();
      _notifyNativeDataChanged('task', task.id);
      return true;
    } catch (e) {
      // 恢复失败，把任务放回缓存
      _recentlyDeletedTasks[id] = task;
      _error = e.toString();
      notifyListeners();
      return false;
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
    _filteredTasksCache = null;
    notifyListeners();
  }

  /// 设置筛选优先级
  void setFilterPriority(TaskPriority? priority) {
    _filterPriority = priority;
    _filteredTasksCache = null;
    notifyListeners();
  }

  /// 设置筛选标签
  void setFilterTag(String? tagId) {
    _filterTagId = tagId;
    _filteredTasksCache = null;
    notifyListeners();
  }

  /// 设置搜索关键词（每次按键触发，不记录搜索历史——避免 I/O 风暴和数据污染）
  void setSearchQuery(String query) {
    _searchQuery = query;
    _filteredTasksCache = null;
    notifyListeners();
  }

  /// 提交搜索（用户按回车/搜索键时调用），才记录到搜索历史
  void commitSearch() {
    if (_searchQuery.trim().isNotEmpty) _addRecentSearch(_searchQuery.trim());
  }

  void setFilterDateRange(DateTime? from, DateTime? to) {
    _filterDateFrom = from;
    _filterDateTo = to;
    _filteredTasksCache = null;
    notifyListeners();
  }

  DateTime? get filterDateFrom => _filterDateFrom;
  DateTime? get filterDateTo => _filterDateTo;
  List<String> get recentSearches => _recentSearches;

  void _addRecentSearch(String query) {
    _recentSearches =
        [query, ..._recentSearches.where((s) => s != query)].take(10).toList();
    _saveRecentSearches();
  }

  void clearRecentSearches() {
    _recentSearches = [];
    _saveRecentSearches();
    notifyListeners();
  }

  Future<void> _saveRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recentSearches', _recentSearches);
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    _recentSearches = prefs.getStringList('recentSearches') ?? [];
  }

  /// 清除所有筛选
  void clearFilters() {
    _filterStatus = null;
    _filterPriority = null;
    _filterTagId = null;
    _searchQuery = '';
    _filteredTasksCache = null;
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
      // Clean up tag references in all tasks
      for (int i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.tagIds.contains(id)) {
          final updatedTagIds = task.tagIds.where((tid) => tid != id).toList();
          final updated =
              task.copyWith(tagIds: updatedTagIds.isEmpty ? [] : updatedTagIds);
          await _storage.updateTask(updated);
          _tasks[i] = updated;
        }
      }
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
      _cachedCompletedTasks = [];
      _cachedActiveTasks = [];
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

      // 导入前强制生成一份自动备份，防止导入覆盖后无法恢复
      _lastAutoBackupAt = null;
      final backupOk = await _triggerAutoBackup();
      if (!backupOk) {
        debugPrint('⚠️ 导入前备份失败，继续导入但无回滚点');
      }

      // 解析任务列表（按 updatedAt 比对，避免旧备份覆盖本地新数据）
      final tasksData = data['tasks'] as List?;
      if (tasksData != null) {
        debugPrint('准备导入 ${tasksData.length} 个任务');
        // 建立本地任务的 updatedAt 索引
        final localUpdatedMap = {
          for (final t in _tasks) t.id: t.updatedAt,
        };
        int imported = 0, skipped = 0;
        for (final taskData in tasksData) {
          try {
            final task = Task.fromJson(taskData as Map<String, dynamic>);
            // 碰撞检测：本地已有同 ID 且本地更新时不覆盖
            final localUpdatedAt = localUpdatedMap[task.id];
            if (localUpdatedAt != null &&
                task.updatedAt.isBefore(localUpdatedAt)) {
              debugPrint('跳过任务（本地更新）: ${task.title}');
              skipped++;
              continue;
            }
            await _storage.insertTask(task);
            imported++;
          } catch (e) {
            debugPrint('导入任务失败: $e');
          }
        }
        debugPrint('任务导入完成: 导入 $imported, 跳过(本地更新) $skipped');
      }

      // 解析标签列表（标签无 updatedAt，采用「不存在才导入」策略，
      // 避免覆盖本地用户已修改的颜色/排序）
      final tagsData = data['tags'] as List?;
      if (tagsData != null) {
        debugPrint('准备导入 ${tagsData.length} 个标签');
        final localTagIds = _tags.map((t) => t.id).toSet();
        for (final tagData in tagsData) {
          try {
            final tag = Tag.fromJson(tagData as Map<String, dynamic>);
            if (localTagIds.contains(tag.id)) {
              debugPrint('跳过标签（本地已存在）: ${tag.name}');
              continue;
            }
            await _storage.insertTag(tag);
            debugPrint('导入标签: ${tag.name}');
          } catch (e) {
            debugPrint('导入标签失败: $e');
          }
        }
      }

      // 解析习惯列表（v2.0 备份格式新增）
      final habitsData = data['habits'] as List?;
      if (habitsData != null) {
        debugPrint('准备导入 ${habitsData.length} 个习惯');
        final dbHelper = DatabaseHelper();
        final existingHabitIds =
            (await dbHelper.getAllHabits()).map((h) => h.id).toSet();
        for (final habitData in habitsData) {
          try {
            final habit = Habit.fromJson(habitData as Map<String, dynamic>);
            // 习惯不存在时才导入，已存在则跳过（避免覆盖用户当前习惯配置）
            if (!existingHabitIds.contains(habit.id)) {
              await dbHelper.insertHabit(habit);
              debugPrint('导入习惯: ${habit.title}');
            }
          } catch (e) {
            debugPrint('导入习惯失败: $e');
          }
        }
      }

      // 解析习惯日志（v2.0 备份格式新增）
      final habitLogsData = data['habitLogs'] as List?;
      if (habitLogsData != null) {
        debugPrint('准备导入 ${habitLogsData.length} 条习惯日志');
        final dbHelper = DatabaseHelper();
        for (final logData in habitLogsData) {
          try {
            final log = HabitLog.fromJson(logData as Map<String, dynamic>);
            await dbHelper.insertHabitLog(log);
          } catch (e) {
            debugPrint('导入习惯日志失败: $e');
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

  /// 手动从后台拉取任务，保持本地优先：仅新增本地不存在的云端任务。
  Future<int> syncFromBackend() async {
    if (_isSyncRunning) return 0;
    _isSyncRunning = true;

    _setBackendSyncing(true);
    try {
      await _backend.init();
      if (!_backend.isLoggedIn) {
        _isSyncRunning = false;
        return 0;
      }

      final lastSyncAt = await _backend.getLastSyncAt();
      final pullResult = await _backend.pullTasks(
          since: lastSyncAt, localTasks: List.of(_tasks));
      var changed = 0;

      for (final remoteTask in pullResult.tasks) {
        final index = _tasks.indexWhere((task) => task.id == remoteTask.id);
        if (index == -1) {
          final withBase =
              remoteTask.copyWith(lastSyncedServerData: remoteTask.toJson());
          await _storage.insertTask(withBase);
          _tasks.insert(0, withBase);
          changed++;
          continue;
        }

        final localTask = _tasks[index];
        if (remoteTask.updatedAt.isAfter(localTask.updatedAt)) {
          final withBase =
              remoteTask.copyWith(lastSyncedServerData: remoteTask.toJson());
          await _storage.updateTask(withBase);
          _tasks[index] = withBase;
          changed++;
        }
      }

      // 删除远端已删除的任务
      for (final deletedId in pullResult.deletedTaskIds) {
        final index = _tasks.indexWhere((task) => task.id == deletedId);
        if (index != -1) {
          await _storage.deleteTask(deletedId);
          _tasks.removeAt(index);
          changed++;
        }
        await SyncQueueService.instance.removeByTaskId(deletedId);
      }

      // push 待同步评论，再保存 pull 返回的远端评论
      await _syncPendingComments();
      if (pullResult.comments.isNotEmpty) {
        await TaskCommentService.instance
            .saveRemoteComments(pullResult.comments);
      }

      // 更新分发缓存
      try {
        final distributions = await _backend.getDistributions();
        _distributions = distributions;
        _distributedTaskIds = distributions
            .where((d) => d.sourceTaskId != null)
            .map((d) => d.sourceTaskId!)
            .toSet();
      } catch (_) {}

      _lastBackendSyncAt = DateTime.now();
      _backendSyncError = null;
      if (changed > 0) {
        _refreshTaskLists();
      }
      await _saveBackendSyncState();
      notifyListeners();
      return changed;
    } catch (e) {
      _backendSyncError = e.toString();
      await _saveBackendSyncState();
      notifyListeners();
      rethrow;
    } finally {
      _isSyncRunning = false;
      _setBackendSyncing(false);
    }
  }

  /// 登录后首次同步：先拉取云端变更，再上传本机任务。
  Future<int> syncAllWithBackend() async {
    if (_isSyncRunning) return 0;
    _isSyncRunning = true;

    _setBackendSyncing(true);

    try {
      await _backend.init();
      if (!_backend.isLoggedIn) {
        _isSyncRunning = false;
        return 0;
      }
      // 先处理重试队列
      final retrySucceeded = await SyncQueueService.instance.retryAll();
      _pendingBackendSyncCount =
          (_pendingBackendSyncCount - retrySucceeded).clamp(0, 999999);

      // 先 pull：获取远端最新数据（包括 admin 修改的），更新本地
      final lastSyncAt = await _backend.getLastSyncAt();
      final pullResult = await _backend.pullTasks(
          since: lastSyncAt, localTasks: List.of(_tasks));
      var changed = 0;
      for (final remoteTask in pullResult.tasks) {
        final index = _tasks.indexWhere((task) => task.id == remoteTask.id);
        if (index == -1) {
          final withBase =
              remoteTask.copyWith(lastSyncedServerData: remoteTask.toJson());
          await _storage.insertTask(withBase);
          _tasks.insert(0, withBase);
          changed++;
          continue;
        }
        final localTask = _tasks[index];
        if (remoteTask.updatedAt.isAfter(localTask.updatedAt)) {
          final withBase =
              remoteTask.copyWith(lastSyncedServerData: remoteTask.toJson());
          await _storage.updateTask(withBase);
          _tasks[index] = withBase;
          changed++;
        }
      }
      for (final deletedId in pullResult.deletedTaskIds) {
        final index = _tasks.indexWhere((task) => task.id == deletedId);
        if (index != -1) {
          await _storage.deleteTask(deletedId);
          _tasks.removeAt(index);
          changed++;
        }
        await SyncQueueService.instance.removeByTaskId(deletedId);
      }
      if (pullResult.comments.isNotEmpty) {
        await TaskCommentService.instance
            .saveRemoteComments(pullResult.comments);
      }

      // 后 push：只推送自上次同步后变化的任务（本地改动），未变化的不重复全量推送，
      // 大幅减少同步数据量与请求数。首次同步（无 lastSyncAt）仍全量推送；
      // 仍有未解决冲突的任务一并推送，避免增量推送漏掉冲突检测。
      final pushCutoff = _lastBackendSyncAt;
      final conflictTaskIds = _conflicts.map((c) => c.taskId).toSet();
      final changedTasks = pushCutoff == null
          ? List.of(_tasks)
          : _tasks
              .where((t) =>
                  t.updatedAt.isAfter(pushCutoff) ||
                  conflictTaskIds.contains(t.id))
              .toList();
      final pushConflicts = changedTasks.isEmpty
          ? <ConflictInfo>[]
          : await _backend.pushTasks(changedTasks);
      _conflicts = pushConflicts;
      await _syncPendingComments();

      // Auto-ack distributions as "received" for current user
      await _ackReceivedDistributions();

      _lastBackendSyncAt = DateTime.now();
      _backendSyncError = null;
      _pendingBackendSyncCount = 0;
      if (changed > 0) {
        _refreshTaskLists();
      }
      await _saveBackendSyncState();
      notifyListeners();
      return changed;
    } catch (e) {
      _backendSyncError = e.toString();
      await _saveBackendSyncState();
      notifyListeners();
      rethrow;
    } finally {
      _isSyncRunning = false;
      _setBackendSyncing(false);
    }
  }

  Future<void> _syncTaskSilently(Task task, {bool deleted = false}) async {
    final pushPayload = _backend.taskToBackendJson(
      task,
      deletedAt: deleted ? DateTime.now().toIso8601String() : null,
    );
    try {
      await _backend.init();
      if (!_backend.isLoggedIn) return;
      if (_isSyncRunning) {
        // Sync in progress — enqueue for later retry
        await SyncQueueService.instance.enqueue(
          type: deleted ? 'task_delete' : 'task_push',
          payload: pushPayload,
        );
        _pendingBackendSyncCount++;
        if (!_suppressNotify) notifyListeners();
        return;
      }
      await _backend.pushTask(task, deleted: deleted);
      _lastBackendSyncAt = DateTime.now();
      _backendSyncError = null;
      await _saveBackendSyncState();
      if (!_suppressNotify) notifyListeners();
    } on BackendError catch (e) {
      _pendingBackendSyncCount++;
      _backendSyncError = e.message;
      await SyncQueueService.instance.enqueue(
        type: deleted ? 'task_delete' : 'task_push',
        payload: pushPayload,
        error: e.message,
        errorCode: e.code,
      );
      await _saveBackendSyncState();
      if (!_suppressNotify) notifyListeners();
      debugPrint('后台任务同步失败，已加入重试队列: $e');
    } catch (e) {
      _pendingBackendSyncCount++;
      _backendSyncError = e.toString();
      await SyncQueueService.instance.enqueue(
        type: deleted ? 'task_delete' : 'task_push',
        payload: pushPayload,
        error: e.toString(),
      );
      await _saveBackendSyncState();
      if (!_suppressNotify) notifyListeners();
      debugPrint('后台任务同步失败，已加入重试队列: $e');
    }
  }

  /// 解决冲突：keepLocal 强制推送本地版本，keepServer 接受服务器版本
  Future<void> resolveConflict(String taskId,
      {bool keepLocal = true, bool merge = false}) async {
    final conflictIndex = _conflicts.indexWhere((c) => c.taskId == taskId);
    if (conflictIndex == -1) return;
    final conflict = _conflicts[conflictIndex];
    if (merge) {
      // 三路合并：local 改的字段保留本地，server 改的保留服务器，双方都改的取服务器（权威）
      final localIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (localIndex != -1) {
        final localTask = _tasks[localIndex];
        final base = localTask.lastSyncedServerData ?? <String, dynamic>{};
        final localJson = localTask.toJson();
        final serverTask =
            _taskFromBackendJson(conflict.serverVersion, localTask: localTask);
        final serverJson = serverTask.toJson();
        final mergedJson = _threeWayMerge(base, localJson, serverJson);
        final serverVersion = (conflict.serverVersion['version'] as int?) ?? 0;
        final localVersion = localTask.version ?? 0;
        // forcePush 后服务器 version = serverVersion + 1；合并结果设为 serverVersion + 2，
        // 使下次 push 的 version 严格大于服务器，走后端“接受”分支（version > existing），
        // 避免落入 isIdentical 严格字段比较而误报冲突（死循环）。
        mergedJson['version'] = (localVersion > serverVersion + 1
                ? localVersion
                : serverVersion + 1) +
            1;
        mergedJson['updated_at'] = DateTime.now().toIso8601String();
        final mergedTask = Task.fromJson(mergedJson)
            .copyWith(lastSyncedServerData: serverJson);
        await _storage.updateTask(mergedTask);
        _tasks[localIndex] = mergedTask;
        _refreshTaskLists();
        final payload = _backend.taskToBackendJson(mergedTask);
        payload['updatedAt'] = DateTime.now().toIso8601String();
        await _backend.forcePushTasks([payload]);
      }
    } else if (keepLocal) {
      final payload = Map<String, dynamic>.from(conflict.clientVersion);
      payload['updatedAt'] = DateTime.now().toIso8601String();
      await _backend.forcePushTasks([payload]);
      final localIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (localIndex != -1) {
        final serverVersion = conflict.serverVersion['version'] as int? ?? 0;
        final localVersion = _tasks[localIndex].version ?? 0;
        // forcePush 后服务器 version = serverVersion + 1。本地设为 serverVersion + 2，
        // 使下次 push 走后端“接受”分支（version > existing），避免落入 isIdentical
        // 严格字段比较而误报冲突（“全部本地”后再次同步又冲突的死循环）。
        final newVersion = (localVersion > serverVersion + 1
                ? localVersion
                : serverVersion + 1) +
            1;
        final newBase = Map<String, dynamic>.from(payload)
          ..['version'] = newVersion;
        _tasks[localIndex] = _tasks[localIndex].copyWith(
          updatedAt: DateTime.now(),
          version: newVersion,
          lastSyncedServerData: newBase,
        );
        await _storage.updateTask(_tasks[localIndex]);
        _refreshTaskLists();
      }
    } else {
      final serverData = conflict.serverVersion;
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        final localTask = _tasks[index];
        final remoteTask =
            _taskFromBackendJson(serverData, localTask: localTask);
        await _storage.updateTask(remoteTask);
        _tasks[index] = remoteTask;
        _refreshTaskLists();
        // No need to push back — server already has this version
      }
    }
    _conflicts.removeWhere((c) => c.taskId == taskId);
    notifyListeners();
  }

  /// 三路合并：基于 base（上次同步的服务端快照），逐字段合并 local 与 server。
  /// local 改的字段保留本地，server 改的保留服务器，双方都改的取服务器（权威）。
  Map<String, dynamic> _threeWayMerge(Map<String, dynamic> base,
      Map<String, dynamic> local, Map<String, dynamic> server) {
    const fields = [
      'title',
      'content',
      'status',
      'priority',
      'start_time',
      'due_time',
      'completed_at',
      'assignee',
      'parent_id',
      'is_recurring',
      'recurring_rule',
      'tag_ids',
      'reminder_minutes',
      'reminder_dismissed',
      'reminder_voice_enabled',
      'sort_order',
      'assignee_user_id',
    ];
    final result = Map<String, dynamic>.from(local);
    for (final f in fields) {
      final b = base[f];
      final l = local[f];
      final s = server[f];
      if (l == s) {
        result[f] = l;
      } else if (l == b) {
        result[f] = s; // local 未改 → 取 server
      } else if (s == b) {
        result[f] = l; // server 未改 → 取 local
      } else {
        result[f] = s; // 双方都改 → 取 server（权威）
      }
    }
    return result;
  }

  // Batch operations
  Future<void> batchUpdateTasks(List<String> ids,
      {TaskStatus? status, String? tagId, bool addTag = true}) async {
    _suppressNotify = true;
    try {
      for (final id in ids) {
        try {
          final index = _tasks.indexWhere((t) => t.id == id);
          if (index == -1) continue;
          var task = _tasks[index];
          final wasCompleted = task.status == TaskStatus.completed;
          if (status != null) {
            task = task.copyWith(status: status);
            if (status == TaskStatus.completed) {
              task = task.copyWith(completedAt: DateTime.now());
            }
          }
          if (tagId != null) {
            final tags = List<String>.from(task.tagIds);
            if (addTag && !tags.contains(tagId)) {
              tags.add(tagId);
            } else if (!addTag) {
              tags.remove(tagId);
            }
            task = task.copyWith(tagIds: tags);
          }
          task = task.copyWith(
            version: (task.version ?? 1) + 1,
            updatedAt: DateTime.now(),
          );
          _tasks[index] = task;
          await _storage.updateTask(task);
          _syncTaskSilently(task);
          // 周期任务批量完成时创建下一期
          if (!wasCompleted &&
              task.status == TaskStatus.completed &&
              task.isRecurring) {
            await _createRecurringTask(task);
          }
        } catch (e) {
          debugPrint('批量更新任务 $id 失败: $e');
        }
      }
      _refreshTaskLists();
      notifyListeners();
    } finally {
      _suppressNotify = false;
    }
  }

  Future<void> batchDeleteTasks(List<String> ids) async {
    final toDelete = ids.where((id) => _tasks.any((t) => t.id == id)).toList();
    final deleteSet = toDelete.toSet();
    // Preserve task data before removal for sync
    final tasksToDelete = {
      for (final id in toDelete) id: _tasks.firstWhere((t) => t.id == id)
    };
    // Persist deletions first
    for (final id in toDelete) {
      await _storage.deleteTask(id);
    }
    _tasks.removeWhere((t) => deleteSet.contains(t.id));
    _refreshTaskLists();
    notifyListeners();
    // Sync with real task data (preserves version, ownerUserId, etc.)
    _suppressNotify = true;
    try {
      for (final id in toDelete) {
        final task = tasksToDelete[id];
        _syncTaskSilently(task ?? Task(id: id, title: ''), deleted: true);
      }
    } finally {
      _suppressNotify = false;
    }
  }

  // Subtask helpers
  Map<String, List<Task>> get subtasksByParentId {
    final map = <String, List<Task>>{};
    for (final t in _tasks) {
      if (t.parentId != null) {
        (map[t.parentId!] ??= []).add(t);
      }
    }
    return map;
  }

  int subtaskCompletedCount(String parentId) {
    return _tasks.where((t) => t.parentId == parentId && t.isCompleted).length;
  }

  Task _taskFromBackendJson(Map<String, dynamic> json, {Task? localTask}) {
    return BackendApiService.instance
        .taskFromBackendJson(json, localTask: localTask);
  }

  Future<int> _syncPendingComments() async {
    return TaskCommentService.instance.syncPendingComments(
      backend: _backend,
      ensureTaskSynced: (taskId) async {
        final index = _tasks.indexWhere((task) => task.id == taskId);
        if (index == -1) {
          throw Exception('评论所属任务已不存在');
        }
        await _backend.pushTask(_tasks[index]);
      },
    );
  }

  Future<void> _ackReceivedDistributions() async {
    final userId = _backend.userId;
    if (userId == null) return;
    for (final d in _distributions) {
      if (d.recipientUserId == userId &&
          (d.status == 'generated' || d.status == 'sent')) {
        try {
          await _backend.ackDistribution(d.id, status: 'received');
        } catch (_) {}
      }
    }
  }

  Future<void> ackDistributionViewed(String distributionId) async {
    try {
      await _backend.ackDistribution(distributionId, status: 'viewed');
    } catch (_) {}
  }

  Future<void> _loadBackendSyncState() async {
    await SyncQueueService.instance.load();
    await _loadRecentSearches();
    final prefs = await SharedPreferences.getInstance();
    _pendingBackendSyncCount = prefs.getInt('backend.pendingSyncCount') ?? 0;
    _backendSyncError = prefs.getString('backend.syncError');
    final lastSync = prefs.getString('backend.lastSyncAt');
    _lastBackendSyncAt =
        lastSync == null ? _lastBackendSyncAt : DateTime.tryParse(lastSync);
  }

  Future<void> _saveBackendSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('backend.pendingSyncCount', _pendingBackendSyncCount);
    if (_backendSyncError == null) {
      await prefs.remove('backend.syncError');
    } else {
      await prefs.setString('backend.syncError', _backendSyncError!);
    }
    if (_lastBackendSyncAt != null) {
      await prefs.setString(
        'backend.lastSyncAt',
        _lastBackendSyncAt!.toIso8601String(),
      );
    }
  }

  void _setBackendSyncing(bool value) {
    _isBackendSyncing = value;
    notifyListeners();
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

        // 重置存储服务单例，确保使用新的数据库连接
        resetStorageService();
        _storage = getStorageService();
        debugPrint('存储服务单例已重置');

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

  // ==================== 任务模板 ====================
  //
  // 模板存储在 SharedPreferences（JSON 数组），避免 DB schema 变更。
  // 模板保留创建任务所需字段（标题、描述、优先级、标签、提醒、周期等），
  // 不含运行时状态（id/状态/时间戳）。

  static const String _templatesPrefsKey = 'task_templates_v1';

  /// 获取所有任务模板（按创建时间倒序）。
  Future<List<Task>> getTaskTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_templatesPrefsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('加载任务模板失败: $e');
      return [];
    }
  }

  /// 将任务保存为模板（保留标题、描述、优先级、标签、提醒、周期等配置）。
  Future<void> saveTaskAsTemplate(Task task) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templates = await getTaskTemplates();

      // 模板副本：清空运行时字段，生成新模板 id
      final template = task.copyWith(
        id: 'tpl_${const Uuid().v4()}',
        status: TaskStatus.pending,
        createdAt: DateTime.now(),
        completedAt: null,
        startTime: null,
        version: 1,
      );
      templates.insert(0, template);
      await prefs.setString(_templatesPrefsKey,
          jsonEncode(templates.map((t) => t.toJson()).toList()));
      debugPrint('已保存任务模板: ${template.title}');
    } catch (e) {
      debugPrint('保存任务模板失败: $e');
      rethrow;
    }
  }

  /// 从模板创建一个新任务（生成新 id，状态重置为待处理，不设截止时间）。
  Future<Task> createTaskFromTemplate(String templateId) async {
    final templates = await getTaskTemplates();
    final tpl = templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw Exception('模板不存在: $templateId'),
    );
    final newTask = tpl.copyWith(
      id: const Uuid().v4(),
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      completedAt: null,
      dueTime: null,
      startTime: null,
      version: 1,
    );
    await addTask(newTask);
    return newTask;
  }

  /// 删除模板。
  Future<void> deleteTaskTemplate(String templateId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templates = await getTaskTemplates();
      templates.removeWhere((t) => t.id == templateId);
      await prefs.setString(_templatesPrefsKey,
          jsonEncode(templates.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('删除任务模板失败: $e');
    }
  }
}
