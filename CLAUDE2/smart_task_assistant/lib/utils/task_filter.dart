import '../models/task.dart';

/// 任务过滤器工具类
/// 统一处理任务的各种筛选和分类逻辑
class TaskFilter {
  /// 获取今日任务
  /// 显示所有未完成的任务 + 今天创建或截止的任务（包括已完成）
  static List<Task> getTodayTasks(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return tasks.where((t) {
      // 优先包含所有未完成的任务（这样导入的历史任务也能显示）
      if (!t.isCompleted) {
        return true;
      }

      // 包含今天创建的任务（即使已完成）
      final createdDate = t.createdAt;
      if (createdDate.year == now.year &&
          createdDate.month == now.month &&
          createdDate.day == now.day) {
        return true;
      }
    
      // 包含今天截止的任务（即使已完成）
      if (t.dueTime != null) {
        final due = t.dueTime!;
        if (due.isAfter(today) && due.isBefore(tomorrow)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// 获取逾期任务
  /// 未完成、未取消且已过截止时间
  static List<Task> getOverdueTasks(List<Task> tasks) {
    return tasks
        .where(
          (t) =>
              !t.isCompleted && t.status != TaskStatus.cancelled && t.isOverdue,
        )
        .toList();
  }

  /// 按状态筛选任务
  static List<Task> filterByStatus(List<Task> tasks, TaskStatus? status) {
    if (status == null) return tasks;
    return tasks.where((t) => t.status == status).toList();
  }

  /// 按优先级筛选任务
  static List<Task> filterByPriority(List<Task> tasks, TaskPriority? priority) {
    if (priority == null) return tasks;
    return tasks.where((t) => t.priority == priority).toList();
  }

  /// 按标签筛选任务
  static List<Task> filterByTag(List<Task> tasks, String? tagId) {
    if (tagId == null) return tasks;
    return tasks.where((t) => t.tagIds.contains(tagId)).toList();
  }

  /// 按关键词搜索任务
  static List<Task> searchByKeyword(List<Task> tasks, String keyword) {
    if (keyword.isEmpty) return tasks;
    final lowerKeyword = keyword.toLowerCase();
    return tasks
        .where(
          (t) =>
              t.title.toLowerCase().contains(lowerKeyword) ||
              (t.content?.toLowerCase().contains(lowerKeyword) ?? false),
        )
        .toList();
  }

  /// 组合筛选
  /// 支持状态、优先级、标签和关键词的组合筛选
  static List<Task> filterTasks({
    required List<Task> tasks,
    TaskStatus? status,
    TaskPriority? priority,
    String? tagId,
    String? keyword,
  }) {
    var result = tasks;

    if (status != null) {
      result = filterByStatus(result, status);
    }

    if (priority != null) {
      result = filterByPriority(result, priority);
    }

    if (tagId != null) {
      result = filterByTag(result, tagId);
    }

    if (keyword != null && keyword.isNotEmpty) {
      result = searchByKeyword(result, keyword);
    }

    return result;
  }

  /// 获取统计数据
  static Map<String, int> getTaskStats(List<Task> tasks) {
    final total = tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;
    final pending = tasks.where((t) => t.status == TaskStatus.pending).length;
    final inProgress =
        tasks.where((t) => t.status == TaskStatus.inProgress).length;
    final overdue = getOverdueTasks(tasks).length;

    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'inProgress': inProgress,
      'overdue': overdue,
    };
  }

  /// 获取高优先级任务
  static List<Task> getHighPriorityTasks(List<Task> tasks) {
    return tasks.where((t) => t.priority == TaskPriority.high).toList();
  }

  /// 获取今日未完成任务
  static List<Task> getTodayUncompletedTasks(List<Task> tasks) {
    final todayTasks = getTodayTasks(tasks);
    return todayTasks.where((t) => !t.isCompleted).toList();
  }

  /// 获取今日已完成任务
  static List<Task> getTodayCompletedTasks(List<Task> tasks) {
    final todayTasks = getTodayTasks(tasks);
    return todayTasks.where((t) => t.isCompleted).toList();
  }

  /// 按优先级排序任务（高优先级在前）
  static List<Task> sortByPriority(List<Task> tasks, {bool descending = true}) {
    final sorted = List<Task>.from(tasks);
    sorted.sort((a, b) {
      final comparison = a.priority.index.compareTo(b.priority.index);
      return descending ? -comparison : comparison;
    });
    return sorted;
  }

  /// 按截止时间排序任务（最早在前）
  static List<Task> sortByDueTime(List<Task> tasks, {bool ascending = true}) {
    final sorted = List<Task>.from(tasks);
    sorted.sort((a, b) {
      if (a.dueTime == null && b.dueTime == null) return 0;
      if (a.dueTime == null) return 1;
      if (b.dueTime == null) return -1;
      final comparison = a.dueTime!.compareTo(b.dueTime!);
      return ascending ? comparison : -comparison;
    });
    return sorted;
  }

  /// 按创建时间排序任务（最新在前）
  static List<Task> sortByCreatedAt(List<Task> tasks,
      {bool descending = true}) {
    final sorted = List<Task>.from(tasks);
    sorted.sort((a, b) {
      final comparison = a.createdAt.compareTo(b.createdAt);
      return descending ? -comparison : comparison;
    });
    return sorted;
  }

  /// 验证任务是否需要提醒
  static bool shouldRemind(Task task) {
    if (task.dueTime == null || task.reminderMinutes == null) {
      return false;
    }
    if (task.isCompleted || task.status == TaskStatus.cancelled) {
      return false;
    }
    if (task.reminderDismissed) {
      return false;
    }

    final now = DateTime.now();
    final reminderTime = task.dueTime!.subtract(
      Duration(minutes: task.reminderMinutes!),
    );

    // 检查是否在提醒时间窗口内（提前5分钟到提醒时间后1分钟）
    final windowStart = reminderTime.subtract(const Duration(minutes: 5));
    final windowEnd = reminderTime.add(const Duration(minutes: 1));

    return now.isAfter(windowStart) && now.isBefore(windowEnd);
  }
}
