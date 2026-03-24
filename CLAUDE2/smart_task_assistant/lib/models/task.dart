import 'dart:convert';

/// 任务状态枚举
enum TaskStatus {
  pending, // 待处理
  inProgress, // 进行中
  completed, // 已完成
  cancelled, // 已取消
}

/// 任务优先级枚举
enum TaskPriority {
  low, // 低
  medium, // 中
  high, // 高
}

/// 任务模型
class Task {
  final String id;
  String title;
  String? content;
  TaskStatus status;
  TaskPriority priority;
  DateTime? startTime;
  DateTime? dueTime;
  DateTime? completedAt;
  String? assignee;
  String? parentId; // 父任务ID，用于子任务
  bool isRecurring;
  String? recurringRule;
  DateTime createdAt;
  DateTime updatedAt;
  List<String> tagIds;
  List<String> attachmentPaths;
  int? reminderMinutes; // 提前提醒分钟数，如 15 表示提前15分钟提醒
  bool reminderDismissed; // 用户是否已关闭提醒

  Task({
    required this.id,
    required this.title,
    this.content,
    this.status = TaskStatus.pending,
    this.priority = TaskPriority.medium,
    this.startTime,
    this.dueTime,
    this.completedAt,
    this.assignee,
    this.parentId,
    this.isRecurring = false,
    this.recurringRule,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tagIds,
    List<String>? attachmentPaths,
    this.reminderMinutes,
    this.reminderDismissed = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tagIds = tagIds ?? [],
        attachmentPaths = attachmentPaths ?? [];

  /// 是否已完成
  bool get isCompleted => status == TaskStatus.completed;

  /// 是否已逾期
  bool get isOverdue {
    if (dueTime == null || isCompleted) return false;
    return DateTime.now().isAfter(dueTime!);
  }

  /// 是否今天到期
  bool get isDueToday {
    if (dueTime == null) return false;
    final now = DateTime.now();
    return dueTime!.year == now.year &&
        dueTime!.month == now.month &&
        dueTime!.day == now.day;
  }

  /// 是否明天到期
  bool get isDueTomorrow {
    if (dueTime == null) return false;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return dueTime!.year == tomorrow.year &&
        dueTime!.month == tomorrow.month &&
        dueTime!.day == tomorrow.day;
  }

  /// 截止时间描述
  String get dueTimeDescription {
    if (dueTime == null) return '';
    if (isOverdue) return '已逾期';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(dueTime!.year, dueTime!.month, dueTime!.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (dueDate == today) {
      return '今天 ${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}';
    }
    if (dueDate == tomorrow) {
      return '明天 ${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}';
    }
    return '${dueTime!.month}月${dueTime!.day}日';
  }

  /// 从 JSON 创建
  factory Task.fromJson(Map<String, dynamic> json) {
    // 验证必需字段
    final id = json['id'];
    final title = json['title'];
    final createdAtStr = json['created_at'];
    final updatedAtStr = json['updated_at'];

    if (id == null || title == null || createdAtStr == null || updatedAtStr == null) {
      throw FormatException(
        'Invalid task JSON: missing required fields. '
        'Required: id, title, created_at, updated_at. '
        'Got: ${json.keys.join(", ")}'
      );
    }

    try {
      return Task(
        id: id as String,
        title: title as String,
        content: json['content'] as String?,
        status: TaskStatus.values[json['status'] as int? ?? 0],
        priority: TaskPriority.values[json['priority'] as int? ?? 1],
        startTime: json['start_time'] != null
            ? DateTime.parse(json['start_time'] as String)
            : null,
        dueTime: json['due_time'] != null
            ? DateTime.parse(json['due_time'] as String)
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
        assignee: json['assignee'] as String?,
        parentId: json['parent_id'] as String?,
        isRecurring: json['is_recurring'] is bool
            ? json['is_recurring'] as bool
            : (json['is_recurring'] as int? ?? 0) == 1,
        recurringRule: json['recurring_rule'] as String?,
        createdAt: DateTime.parse(createdAtStr as String),
        updatedAt: DateTime.parse(updatedAtStr as String),
        tagIds: json['tag_ids'] != null
            ? List<String>.from(jsonDecode(json['tag_ids'] as String))
            : [],
        attachmentPaths: json['attachment_paths'] != null
            ? List<String>.from(jsonDecode(json['attachment_paths'] as String))
            : [],
        reminderMinutes: json['reminder_minutes'] as int?,
        reminderDismissed: json['reminder_dismissed'] is bool
            ? json['reminder_dismissed'] as bool
            : (json['reminder_dismissed'] as int? ?? 0) == 1,
      );
    } on FormatException {
      rethrow; // 重新抛出格式异常
    } catch (e) {
      throw FormatException('Failed to parse task JSON: $e');
    }
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'status': status.index,
      'priority': priority.index,
      'start_time': startTime?.toIso8601String(),
      'due_time': dueTime?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'assignee': assignee,
      'parent_id': parentId,
      'is_recurring': isRecurring,
      'recurring_rule': recurringRule,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tag_ids': jsonEncode(tagIds),
      'attachment_paths': jsonEncode(attachmentPaths),
      'reminder_minutes': reminderMinutes,
      'reminder_dismissed': reminderDismissed,
    };
  }

  /// 复制并修改
  Task copyWith({
    String? id,
    String? title,
    String? content,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? startTime,
    DateTime? dueTime,
    DateTime? completedAt,
    String? assignee,
    String? parentId,
    bool? isRecurring,
    String? recurringRule,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tagIds,
    List<String>? attachmentPaths,
    int? reminderMinutes,
    bool? reminderDismissed,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      startTime: startTime ?? this.startTime,
      dueTime: dueTime ?? this.dueTime,
      completedAt: completedAt ?? this.completedAt,
      assignee: assignee ?? this.assignee,
      parentId: parentId ?? this.parentId,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringRule: recurringRule ?? this.recurringRule,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      tagIds: tagIds ?? List.from(this.tagIds),
      attachmentPaths: attachmentPaths ?? List.from(this.attachmentPaths),
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      reminderDismissed: reminderDismissed ?? this.reminderDismissed,
    );
  }
}

/// AI识别结果
class AIParsedTask {
  final String title;
  final String? content;
  final DateTime? dueTime;
  final TaskPriority priority;
  final String? assignee;
  final List<String> tags;

  AIParsedTask({
    required this.title,
    this.content,
    this.dueTime,
    this.priority = TaskPriority.medium,
    this.assignee,
    this.tags = const [],
  });
}
