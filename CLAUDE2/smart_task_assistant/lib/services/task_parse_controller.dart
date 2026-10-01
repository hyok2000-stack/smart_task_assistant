import '../models/task.dart';
import 'ai_service.dart';

/// ParsedTask → 表单选择值的映射结果（TaskParseController.resolve 的产物）。
class TaskSelection {
  final TaskPriority priority;
  final DateTime? dueTime;
  final List<String> tags;

  /// 推荐提醒分钟数；null 表示解析未给出推荐，表单保持现状
  final int? reminderMinutes;
  final bool showCustomReminder;
  final int? customReminderMinutes;

  const TaskSelection({
    required this.priority,
    required this.dueTime,
    required this.tags,
    required this.reminderMinutes,
    required this.showCustomReminder,
    required this.customReminderMinutes,
  });
}

/// 添加任务双入口（完整表单 AddTaskScreen / 快速添加 QuickAddModal）
/// 共用的解析编排与结果映射。
///
/// 统一三件事，避免两入口各自演化导致行为分叉：
/// 1. 解析链：AI 优先（用户配置的 provider），失败/未配置自动回退本地规则引擎；
/// 2. ParsedTask → 表单选择值的映射（默认标签、提醒推荐、自定义提醒展开）；
/// 3. 预设提醒选项判断。
class TaskParseController {
  TaskParseController._();

  /// 预设提醒选项（分钟）：10分钟、15分钟、30分钟、1小时、1天
  static const List<int> presetReminderOptions = [10, 15, 30, 60, 1440];

  /// 快速添加入口的默认标签（解析无标签时兜底）
  static const List<String> fallbackTags = ['工作'];

  /// AI 优先解析链：加载配置 → AIService.parseTask
  /// （未配置 AI 或调用失败时 AIService 内部已回退本地规则引擎）。
  static Future<ParsedTask?> parseWithEngine(String input) async {
    if (input.trim().isEmpty) return null;
    final ai = AIService();
    await ai.loadConfig();
    return ai.parseTask(input);
  }

  /// 当前解析引擎的展示名（须在 parseWithEngine 之后调用）
  static String engineLabel() =>
      AIService().config.enabled ? 'AI' : '规则';

  /// ParsedTask → 表单选择值。
  ///
  /// [applyReminderRecommendation] 为 true 时一并解析推荐提醒时长
  /// （快速添加入口需要；完整表单的提醒由用户手选，传 false）。
  static TaskSelection resolve(
    ParsedTask parsed, {
    bool applyReminderRecommendation = true,
  }) {
    int? reminderMinutes;
    var showCustom = false;
    int? customMinutes;
    if (applyReminderRecommendation &&
        parsed.recommendedReminderMinutes != null) {
      reminderMinutes = parsed.recommendedReminderMinutes;
      showCustom = !isInPresetReminderOptions(reminderMinutes);
      if (showCustom) customMinutes = reminderMinutes;
    }
    return TaskSelection(
      priority: parsed.priority,
      dueTime: parsed.dueTime,
      tags: parsed.tags.isNotEmpty ? parsed.tags : fallbackTags,
      reminderMinutes: reminderMinutes,
      showCustomReminder: showCustom,
      customReminderMinutes: customMinutes,
    );
  }

  /// 推荐的提醒分钟数是否在预设选项内（null 视为在预设内——不展示自定义输入）
  static bool isInPresetReminderOptions(int? minutes) =>
      minutes == null || presetReminderOptions.contains(minutes);
}
