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

  /// 软删除墓碑：true 表示用户已删除，仅本地保留待同步 DELETE 到后端。
  /// UI 读取（getComments）会过滤掉墓碑；同步成功后硬删除。
  final bool deleted;

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
    this.deleted = false,
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
    bool? deleted,
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
      deleted: deleted ?? this.deleted,
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
      deleted: json['deleted'] as bool? ?? false,
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
      'deleted': deleted,
    };
  }
}
