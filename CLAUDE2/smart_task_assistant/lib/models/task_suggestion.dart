/// AI任务优先级建议
class TaskPrioritySuggestion {
  final String summary; // 总体建议
  final List<TaskSuggestionItem> items; // 具体任务建议
  final bool isFromAI; // 是否来自AI分析

  TaskPrioritySuggestion({
    required this.summary,
    required this.items,
    this.isFromAI = false,
  });

  TaskPrioritySuggestion copyWith({
    String? summary,
    List<TaskSuggestionItem>? items,
    bool? isFromAI,
  }) {
    return TaskPrioritySuggestion(
      summary: summary ?? this.summary,
      items: items ?? this.items,
      isFromAI: isFromAI ?? this.isFromAI,
    );
  }
}

/// 具体任务建议项
class TaskSuggestionItem {
  final String taskId; // 任务ID
  final String title; // 任务标题
  final int recommendedOrder; // 推荐的处理顺序
  final String reason; // 推荐理由
  final String suggestion; // 具体建议
  final String priorityLevel; // 优先级级别（高/中/低）

  TaskSuggestionItem({
    required this.taskId,
    required this.title,
    required this.recommendedOrder,
    required this.reason,
    required this.suggestion,
    required this.priorityLevel,
  });
}
