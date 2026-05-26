class SyncQueueItem {
  final String id;
  final String type; // task_push, task_delete, comment_push, distribution_ack
  final Map<String, dynamic> payload;
  final String? error;
  final String? errorCode;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastRetryAt;

  const SyncQueueItem({
    required this.id,
    required this.type,
    required this.payload,
    this.error,
    this.errorCode,
    this.retryCount = 0,
    required this.createdAt,
    this.lastRetryAt,
  });

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      error: json['error'] as String?,
      errorCode: json['errorCode'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastRetryAt: json['lastRetryAt'] != null
          ? DateTime.parse(json['lastRetryAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'error': error,
        'errorCode': errorCode,
        'retryCount': retryCount,
        'createdAt': createdAt.toIso8601String(),
        'lastRetryAt': lastRetryAt?.toIso8601String(),
      };

  SyncQueueItem copyWith({
    String? error,
    String? errorCode,
    int? retryCount,
    DateTime? lastRetryAt,
  }) {
    return SyncQueueItem(
      id: id,
      type: type,
      payload: payload,
      error: error ?? this.error,
      errorCode: errorCode ?? this.errorCode,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
    );
  }
}
