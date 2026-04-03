/// 习惯日志状态枚举
enum HabitLogStatus {
  completed,  // 已完成
  skipped,    // 未完成/跳过
}

/// 习惯日志模型
class HabitLog {
  final String id;
  final String habitId;       // 关联的习惯 ID
  int count;                 // 完成数量
  HabitLogStatus status;     // 状态: completed/skipped
  DateTime completedAt;     // 完成时间/跳过时间
  DateTime createdAt;

  HabitLog({
    required this.id,
    required this.habitId,
    this.count = 1,
    required this.status,
    required this.completedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从 JSON 创建
  factory HabitLog.fromJson(Map<String, dynamic> json) {
    // 验证必需字段
    final id = json['id'];
    final habitId = json['habit_id'];
    final completedAtStr = json['completed_at'];
    final createdAtStr = json['created_at'];

    if (id == null || habitId == null || completedAtStr == null || createdAtStr == null) {
      throw FormatException(
        'Invalid habit log JSON: missing required fields. '
        'Required: id, habit_id, completed_at, created_at. '
        'Got: ${json.keys.join(", ")}'
      );
    }

    try {
      // 解析状态
      HabitLogStatus parseStatus(int? value) {
        switch (value) {
          case 0:
            return HabitLogStatus.completed;
          case 1:
            return HabitLogStatus.skipped;
          default:
            return HabitLogStatus.completed;
        }
      }

      return HabitLog(
        id: id as String,
        habitId: habitId as String,
        count: json['count'] as int? ?? 1,
        status: parseStatus(json['status'] as int?),
        completedAt: DateTime.parse(completedAtStr as String),
        createdAt: DateTime.parse(createdAtStr as String),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse habit log JSON: $e');
    }
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'habit_id': habitId,
      'count': count,
      'status': status.index,
      'completed_at': completedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  HabitLog copyWith({
    String? id,
    String? habitId,
    int? count,
    HabitLogStatus? status,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return HabitLog(
      id: id ?? this.id,
      habitId: habitId ?? this.habitId,
      count: count ?? this.count,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 是否已完成
  bool get isCompleted => status == HabitLogStatus.completed;

  /// 是否未完成
  bool get isSkipped => status == HabitLogStatus.skipped;
}