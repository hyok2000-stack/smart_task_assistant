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

/// 用于区分"未传参"和"显式传 null"的哨兵值
const Object _sentinel = Object();

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
  DateTime? archivedAt;
  List<String> tagIds;
  List<String> attachmentPaths;
  int? reminderMinutes; // 提前提醒分钟数，如 15 表示提前15分钟提醒
  bool reminderDismissed; // 用户是否已关闭提醒
  bool reminderVoiceEnabled; // 是否启用语音提醒
  String? reminderVoiceType; // 语音类型：male/female/neutral/custom
  String? reminderVoiceStyle; // 语音风格：standard/gentle/lively
  String? reminderVoiceSpeed; // 语音速度：slow/normal/fast
  String? reminderCustomVoicePath; // 自定义语音文件路径
  String? sourceType; // 任务来源：local / team_distribution
  String? sourceTaskId; // 来源任务ID（分发时指向原任务）
  String? sourceDistributionId; // 来源分发ID
  String? teamId; // 所属团队ID
  String? ownerUserId; // 任务所有者ID（后台分配）
  int? version; // 同步版本号，用于冲突检测
  int? sortOrder; // 排序顺序（置顶=-1，默认=0）
  String? assigneeUserId; // 被指派人ID
  Map<String, dynamic>? lastSyncedServerData; // 上次同步的服务端快照（本地JSON），三路合并用，仅本地不上行

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
    this.archivedAt,
    List<String>? tagIds,
    List<String>? attachmentPaths,
    this.reminderMinutes,
    this.reminderDismissed = false,
    this.reminderVoiceEnabled = true,
    this.reminderVoiceType,
    this.reminderVoiceStyle = 'standard',
    this.reminderVoiceSpeed = 'normal',
    this.reminderCustomVoicePath,
    this.sourceType,
    this.sourceTaskId,
    this.sourceDistributionId,
    this.teamId,
    this.ownerUserId,
    this.version,
    this.sortOrder,
    this.assigneeUserId,
    this.lastSyncedServerData,
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

    if (id == null ||
        title == null ||
        createdAtStr == null ||
        updatedAtStr == null) {
      throw FormatException('Invalid task JSON: missing required fields. '
          'Required: id, title, created_at, updated_at. '
          'Got: ${json.keys.join(", ")}');
    }

    try {
      return Task(
        id: id as String,
        title: title as String,
        content: json['content'] as String?,
        status: _parseTaskStatus(json['status'] as int? ?? 0),
        priority: _parseTaskPriority(json['priority'] as int? ?? 1),
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
        archivedAt: json['archived_at'] != null
            ? DateTime.parse(json['archived_at'] as String)
            : null,
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
        reminderVoiceEnabled:
            _parseBoolDefaultTrue(json['reminder_voice_enabled']),
        reminderVoiceType: json['reminder_voice_type'] as String?,
        reminderVoiceStyle: json['reminder_voice_style'] as String?,
        reminderVoiceSpeed: json['reminder_voice_speed'] as String?,
        reminderCustomVoicePath: json['reminder_custom_voice_path'] as String?,
        sourceType: json['source_type'] as String?,
        sourceTaskId: json['source_task_id'] as String?,
        sourceDistributionId: json['source_distribution_id'] as String?,
        teamId: json['team_id'] as String?,
        ownerUserId: json['owner_user_id'] as String?,
        version: json['version'] as int?,
        sortOrder: json['sort_order'] as int?,
        assigneeUserId: json['assignee_user_id'] as String?,
        lastSyncedServerData: json['last_synced_server'] == null
            ? null
            : Map<String, dynamic>.from(
                jsonDecode(json['last_synced_server'] as String) as Map),
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
      'is_recurring': isRecurring ? 1 : 0,
      'recurring_rule': recurringRule,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'archived_at': archivedAt?.toIso8601String(),
      'tag_ids': jsonEncode(tagIds),
      'attachment_paths': jsonEncode(attachmentPaths),
      'reminder_minutes': reminderMinutes,
      'reminder_dismissed': reminderDismissed ? 1 : 0,
      'reminder_voice_enabled': reminderVoiceEnabled ? 1 : 0,
      'reminder_voice_type': reminderVoiceType,
      'reminder_voice_style': reminderVoiceStyle,
      'reminder_voice_speed': reminderVoiceSpeed,
      'reminder_custom_voice_path': reminderCustomVoicePath,
      'source_type': sourceType,
      'source_task_id': sourceTaskId,
      'source_distribution_id': sourceDistributionId,
      'team_id': teamId,
      'owner_user_id': ownerUserId,
      'version': version,
      'sort_order': sortOrder,
      'assignee_user_id': assigneeUserId,
      'last_synced_server': lastSyncedServerData != null
          ? jsonEncode(lastSyncedServerData)
          : null,
    };
  }

  /// 复制并修改
  /// 对于可空的 String? / DateTime? 字段，使用 _sentinel 区分"未传参"和"显式传 null"
  Task copyWith({
    String? id,
    String? title,
    Object? content = _sentinel,
    TaskStatus? status,
    TaskPriority? priority,
    Object? startTime = _sentinel,
    Object? dueTime = _sentinel,
    Object? completedAt = _sentinel,
    Object? assignee = _sentinel,
    Object? parentId = _sentinel,
    bool? isRecurring,
    Object? recurringRule = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? archivedAt = _sentinel,
    List<String>? tagIds,
    List<String>? attachmentPaths,
    Object? reminderMinutes = _sentinel,
    bool? reminderDismissed,
    bool? reminderVoiceEnabled,
    String? reminderVoiceType,
    String? reminderVoiceStyle,
    String? reminderVoiceSpeed,
    Object? reminderCustomVoicePath = _sentinel,
    Object? sourceType = _sentinel,
    Object? sourceTaskId = _sentinel,
    Object? sourceDistributionId = _sentinel,
    Object? teamId = _sentinel,
    Object? ownerUserId = _sentinel,
    int? version,
    int? sortOrder,
    Object? assigneeUserId = _sentinel,
    Map<String, dynamic>? lastSyncedServerData,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      content:
          identical(content, _sentinel) ? this.content : content as String?,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      startTime: identical(startTime, _sentinel)
          ? this.startTime
          : startTime as DateTime?,
      dueTime:
          identical(dueTime, _sentinel) ? this.dueTime : dueTime as DateTime?,
      completedAt: identical(completedAt, _sentinel)
          ? this.completedAt
          : completedAt as DateTime?,
      assignee:
          identical(assignee, _sentinel) ? this.assignee : assignee as String?,
      parentId:
          identical(parentId, _sentinel) ? this.parentId : parentId as String?,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringRule: identical(recurringRule, _sentinel)
          ? this.recurringRule
          : recurringRule as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      archivedAt: identical(archivedAt, _sentinel)
          ? this.archivedAt
          : archivedAt as DateTime?,
      tagIds: tagIds ?? List.from(this.tagIds),
      attachmentPaths: attachmentPaths ?? List.from(this.attachmentPaths),
      reminderMinutes: identical(reminderMinutes, _sentinel)
          ? this.reminderMinutes
          : reminderMinutes as int?,
      reminderDismissed: reminderDismissed ?? this.reminderDismissed,
      reminderVoiceEnabled: reminderVoiceEnabled ?? this.reminderVoiceEnabled,
      reminderVoiceType: reminderVoiceType ?? this.reminderVoiceType,
      reminderVoiceStyle: reminderVoiceStyle ?? this.reminderVoiceStyle,
      reminderVoiceSpeed: reminderVoiceSpeed ?? this.reminderVoiceSpeed,
      reminderCustomVoicePath: identical(reminderCustomVoicePath, _sentinel)
          ? this.reminderCustomVoicePath
          : reminderCustomVoicePath as String?,
      sourceType: identical(sourceType, _sentinel)
          ? this.sourceType
          : sourceType as String?,
      sourceTaskId: identical(sourceTaskId, _sentinel)
          ? this.sourceTaskId
          : sourceTaskId as String?,
      sourceDistributionId: identical(sourceDistributionId, _sentinel)
          ? this.sourceDistributionId
          : sourceDistributionId as String?,
      teamId: identical(teamId, _sentinel) ? this.teamId : teamId as String?,
      ownerUserId: identical(ownerUserId, _sentinel)
          ? this.ownerUserId
          : ownerUserId as String?,
      version: version ?? this.version,
      sortOrder: sortOrder ?? this.sortOrder,
      assigneeUserId: identical(assigneeUserId, _sentinel)
          ? this.assigneeUserId
          : assigneeUserId as String?,
      lastSyncedServerData: lastSyncedServerData ?? this.lastSyncedServerData,
    );
  }
}

TaskStatus _parseTaskStatus(int index) {
  return index >= 0 && index < TaskStatus.values.length
      ? TaskStatus.values[index]
      : TaskStatus.pending;
}

TaskPriority _parseTaskPriority(int index) {
  return index >= 0 && index < TaskPriority.values.length
      ? TaskPriority.values[index]
      : TaskPriority.medium;
}

bool _parseBoolDefaultTrue(dynamic value) {
  if (value == null) return true;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == '0' || normalized == 'false') return false;
    if (normalized == '1' || normalized == 'true') return true;
  }
  return true;
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
