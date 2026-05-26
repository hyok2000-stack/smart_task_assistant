class TaskComment {
  final String id;
  final String taskId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool synced;
  final String? syncError;
  final String operationId;
  final String? authorUserId;
  final String? authorName;
  final String? serverId;

  const TaskComment({
    required this.id,
    required this.taskId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.operationId,
    this.synced = false,
    this.syncError,
    this.authorUserId,
    this.authorName,
    this.serverId,
  });

  TaskComment copyWith({
    String? id,
    String? taskId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? synced,
    String? syncError,
    String? operationId,
    String? authorUserId,
    String? authorName,
    String? serverId,
  }) {
    return TaskComment(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      operationId: operationId ?? this.operationId,
      synced: synced ?? this.synced,
      syncError: syncError,
      authorUserId: authorUserId ?? this.authorUserId,
      authorName: authorName ?? this.authorName,
      serverId: serverId ?? this.serverId,
    );
  }

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    return TaskComment(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      operationId: json['operationId'] as String? ?? json['id'] as String,
      synced: json['synced'] as bool? ?? false,
      syncError: json['syncError'] as String?,
      authorUserId: json['authorUserId'] as String?,
      authorName: json['authorName'] as String?,
      serverId: json['serverId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'operationId': operationId,
      'synced': synced,
      'syncError': syncError,
      if (authorUserId != null) 'authorUserId': authorUserId,
      if (authorName != null) 'authorName': authorName,
      if (serverId != null) 'serverId': serverId,
    };
  }
}
