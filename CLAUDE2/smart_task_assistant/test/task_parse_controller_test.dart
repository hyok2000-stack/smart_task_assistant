// TaskParseController 单元测试：两入口共用的解析编排与结果映射
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/task.dart';
import 'package:smart_task_assistant/services/ai_service.dart';
import 'package:smart_task_assistant/services/task_parse_controller.dart';

void main() {
  group('TaskSelection 映射', () {
    test('完整解析结果：标签保留、预设内推荐提醒直接应用', () {
      final parsed = ParsedTask(
        title: '交日报',
        dueTime: DateTime(2026, 10, 2, 18),
        priority: TaskPriority.high,
        tags: ['工作'],
        recommendedReminderMinutes: 15,
      );
      final s = TaskParseController.resolve(parsed);
      expect(s.priority, TaskPriority.high);
      expect(s.dueTime, DateTime(2026, 10, 2, 18));
      expect(s.tags, ['工作']);
      expect(s.reminderMinutes, 15);
      expect(s.showCustomReminder, isFalse);
      expect(s.customReminderMinutes, isNull);
    });

    test('无标签时回退默认标签「工作」', () {
      final parsed = ParsedTask(title: '开会', tags: []);
      final s = TaskParseController.resolve(parsed);
      expect(s.tags, ['工作']);
    });

    test('非预设推荐提醒（如 AI 推荐的 22 分钟）展开自定义输入', () {
      final parsed = ParsedTask(
        title: '紧急修复',
        tags: ['运维'],
        recommendedReminderMinutes: 22,
      );
      final s = TaskParseController.resolve(parsed);
      expect(s.reminderMinutes, 22);
      expect(s.showCustomReminder, isTrue);
      expect(s.customReminderMinutes, 22);
    });

    test('无推荐提醒 → 保持表单现状（reminderMinutes 为 null）', () {
      final s = TaskParseController.resolve(ParsedTask(title: '散步'));
      expect(s.reminderMinutes, isNull);
      expect(s.showCustomReminder, isFalse);
    });

    test('applyReminderRecommendation=false 时不应用推荐（完整表单模式）', () {
      final parsed = ParsedTask(
        title: '开会',
        recommendedReminderMinutes: 30,
      );
      final s = TaskParseController.resolve(
        parsed,
        applyReminderRecommendation: false,
      );
      expect(s.reminderMinutes, isNull);
      expect(s.showCustomReminder, isFalse);
    });
  });

  group('预设提醒选项判断', () {
    test('null 视为预设内（不展示自定义输入）', () {
      expect(TaskParseController.isInPresetReminderOptions(null), isTrue);
    });

    test('预设值：10/15/30/60/1440', () {
      for (final m in TaskParseController.presetReminderOptions) {
        expect(TaskParseController.isInPresetReminderOptions(m), isTrue,
            reason: '$m 应为预设');
      }
    });

    test('非预设值返回 false', () {
      expect(TaskParseController.isInPresetReminderOptions(22), isFalse);
      expect(TaskParseController.isInPresetReminderOptions(120), isFalse);
    });
  });

  group('解析链编排', () {
    test('空输入直接返回 null', () async {
      expect(await TaskParseController.parseWithEngine('   '), isNull);
    });

    test('未配置 AI 时回退本地规则引擎', () async {
      final r = await TaskParseController.parseWithEngine('明天下午3点开会');
      expect(r, isNotNull);
      expect(r!.title, '开会');
      expect(r.dueTime, isNotNull);
      expect(TaskParseController.engineLabel(), '规则');
    });
  });
}
