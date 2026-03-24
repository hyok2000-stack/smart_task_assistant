/// 任务分发状态枚举
enum DistributionStatus {
  pending, // 待确认
  accepted, // 已接受
  rejected, // 已拒绝
  inProgress, // 进行中
  completed, // 已完成
  cancelled, // 已取消
}

/// 任务分发模型
/// 用于跟踪分发给其他人的任务状态
class TaskDistribution {
  final String id;
  final String taskId; // 关联的原任务ID
  final String assigneeName; // 分发给谁
  final String? assigneeEmail; // 分发对象邮箱
  final String? assigneePhone; // 分发对象电话
  DistributionStatus status;
  DateTime distributedAt;
  DateTime? acceptedAt;
  DateTime? completedAt;
  DateTime? dueDate; // 期望完成日期
  String? notes; // 分发备注
  double progress; // 进度百分比 0-100
  String? responseMessage; // 接收人的回复消息
  DateTime createdAt;
  DateTime updatedAt;

  TaskDistribution({
    required this.id,
    required this.taskId,
    required this.assigneeName,
    this.assigneeEmail,
    this.assigneePhone,
    this.status = DistributionStatus.pending,
    DateTime? distributedAt,
    this.acceptedAt,
    this.completedAt,
    this.dueDate,
    this.notes,
    this.progress = 0.0,
    this.responseMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : distributedAt = distributedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 是否已接受
  bool get isAccepted =>
      status == DistributionStatus.accepted ||
      status == DistributionStatus.inProgress ||
      status == DistributionStatus.completed;

  /// 是否已完成
  bool get isCompleted => status == DistributionStatus.completed;

  /// 是否已逾期
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// 是否即将到期（3天内）
  bool get isDueSoon {
    if (dueDate == null || isCompleted) return false;
    final daysUntilDue = dueDate!.difference(DateTime.now()).inDays;
    return daysUntilDue >= 0 && daysUntilDue <= 3;
  }

  /// 是否待确认
  bool get isPending => status == DistributionStatus.pending;

  /// 状态描述
  String get statusDescription {
    switch (status) {
      case DistributionStatus.pending:
        return '待确认';
      case DistributionStatus.accepted:
        return '已接受';
      case DistributionStatus.rejected:
        return '已拒绝';
      case DistributionStatus.inProgress:
        return '进行中';
      case DistributionStatus.completed:
        return '已完成';
      case DistributionStatus.cancelled:
        return '已取消';
    }
  }

  /// 从 JSON 创建
  factory TaskDistribution.fromJson(Map<String, dynamic> json) {
    return TaskDistribution(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      assigneeName: json['assignee_name'] as String,
      assigneeEmail: json['assignee_email'] as String?,
      assigneePhone: json['assignee_phone'] as String?,
      status: DistributionStatus.values[json['status'] as int? ?? 0],
      distributedAt: DateTime.parse(json['distributed_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      notes: json['notes'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      responseMessage: json['response_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'assignee_name': assigneeName,
      'assignee_email': assigneeEmail,
      'assignee_phone': assigneePhone,
      'status': status.index,
      'distributed_at': distributedAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'notes': notes,
      'progress': progress,
      'response_message': responseMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 复制并修改
  TaskDistribution copyWith({
    String? id,
    String? taskId,
    String? assigneeName,
    String? assigneeEmail,
    String? assigneePhone,
    DistributionStatus? status,
    DateTime? distributedAt,
    DateTime? acceptedAt,
    DateTime? completedAt,
    DateTime? dueDate,
    String? notes,
    double? progress,
    String? responseMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskDistribution(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      assigneeName: assigneeName ?? this.assigneeName,
      assigneeEmail: assigneeEmail ?? this.assigneeEmail,
      assigneePhone: assigneePhone ?? this.assigneePhone,
      status: status ?? this.status,
      distributedAt: distributedAt ?? this.distributedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      progress: progress ?? this.progress,
      responseMessage: responseMessage ?? this.responseMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// 接受任务
  TaskDistribution accept({String? message}) {
    return copyWith(
      status: DistributionStatus.accepted,
      acceptedAt: DateTime.now(),
      responseMessage: message,
    );
  }

  /// 拒绝任务
  TaskDistribution reject({String? message}) {
    return copyWith(
      status: DistributionStatus.rejected,
      responseMessage: message,
    );
  }

  /// 开始任务
  TaskDistribution start() {
    if (!isAccepted) {
      throw StateError('只有已接受的任务才能开始');
    }
    return copyWith(status: DistributionStatus.inProgress);
  }

  /// 更新进度
  TaskDistribution updateProgress(double newProgress) {
    if (newProgress < 0 || newProgress > 100) {
      throw ArgumentError('进度必须在 0-100 之间');
    }
    return copyWith(progress: newProgress);
  }

  /// 完成任务
  TaskDistribution complete() {
    return copyWith(
      status: DistributionStatus.completed,
      progress: 100.0,
      completedAt: DateTime.now(),
    );
  }

  /// 取消任务
  TaskDistribution cancel() {
    return copyWith(status: DistributionStatus.cancelled);
  }
}
