/// AI 自然语言时间解析单元测试
///
/// 锁定 v2.2.10-11 的修复：
/// 1. "X小时后/X天后" 等相对时间必须在具体时间([:点])之前处理，
///    避免 "3小时" 被 timeRegex 的 "3时" 误匹配；
/// 2. 时段换算规则（下午X点→X+12、晚上12点→0点等）；
/// 3. 推荐提醒时长的收敛策略（远期任务最多提前2小时）。
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/task.dart';
import 'package:smart_task_assistant/services/ai_service.dart';

void main() {
  final ai = AIService();

  group('相对时间解析（v2.2.10 核心修复）', () {
    test('3小时后：不再被 "3时" 误匹配，标题干净且时间正确', () {
      final before = DateTime.now();
      final r = ai.parseTaskLocal('3小时后开会');
      final after = DateTime.now();

      expect(r.title, '开会');
      expect(r.dueTime, isNotNull);
      // dueTime 应约等于 now + 3小时（允许测试执行耗时的几秒误差）
      final expectedLow = before.add(const Duration(hours: 3));
      final expectedHigh = after.add(const Duration(hours: 3));
      expect(
        r.dueTime!.isAfter(expectedLow.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(
        r.dueTime!.isBefore(expectedHigh.add(const Duration(seconds: 5))),
        isTrue,
      );
    });

    test('1小时后取快递', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('1小时后取快递');
      expect(r.title, '取快递');
      expect(
        r.dueTime!.difference(now).inMinutes,
        inInclusiveRange(55, 65),
      );
    });

    test('2天后交报告 → 后天18:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('2天后交报告');
      expect(r.title, '交报告');
      expect(r.dueTime, DateTime(now.year, now.month, now.day + 2, 18, 0));
    });

    test('相对时间不被默认时段时间覆盖', () {
      // "开会" 无其他时间词；若 isRelativeTime 守卫失效，
      // 上午运行时 dueTime 会被改成当天 9:00
      final now = DateTime.now();
      final r = ai.parseTaskLocal('2小时后提醒我测试');
      expect(r.title, '提醒我测试');
      expect(
        r.dueTime!.difference(now).inMinutes,
        inInclusiveRange(115, 125),
      );
    });
  });

  group('时段与具体时间换算', () {
    test('明天下午5点开会 → 明天17:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('明天下午5点开会');
      expect(r.title, '开会');
      expect(r.dueTime, DateTime(now.year, now.month, now.day + 1, 17, 0));
    });

    test('下午3点提交周报 → 今天15:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('下午3点提交周报');
      expect(r.title, '提交周报');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 15, 0));
    });

    test('晚上7点吃饭 → 19:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('晚上7点吃饭');
      expect(r.title, '吃饭');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 19, 0));
    });

    test('中午12点吃饭 → 12:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('中午12点吃饭');
      expect(r.title, '吃饭');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 12, 0));
    });

    test('晚上12点睡觉 → 0:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('晚上12点睡觉');
      expect(r.title, '睡觉');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 0, 0));
    });

    test('上午9点开晨会 → 9:00（上午小时数不加12）', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('上午9点开晨会');
      expect(r.title, '开晨会');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 9, 0));
    });

    test('12点30分开会 → 12:30（支持分钟）', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('12点30分开会');
      expect(r.title, '开会');
      expect(r.dueTime, DateTime(now.year, now.month, now.day, 12, 30));
    });
  });

  group('日期关键词解析', () {
    test('明天开会 → 明天18:00（默认时间）', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('明天开会');
      expect(r.title, '开会');
      expect(r.dueTime, DateTime(now.year, now.month, now.day + 1, 18, 0));
    });

    test('后天交报告 → 后天18:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('后天交报告');
      expect(r.title, '交报告');
      expect(r.dueTime, DateTime(now.year, now.month, now.day + 2, 18, 0));
    });

    test('下周三开会 → 下周三18:00', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('下周三开会');
      expect(r.title, '开会');
      final daysUntilNextWeek = 7 - now.weekday + 3;
      expect(
        r.dueTime,
        DateTime(now.year, now.month, now.day + daysUntilNextWeek, 18, 0),
      );
    });

    test('5月1日交总结：月份已过则进位到明年', () {
      final now = DateTime.now();
      final r = ai.parseTaskLocal('5月1日交总结');
      expect(r.title, '交总结');
      // 与实现规则一致：month < now.month 时进位；等于时不进位
      final expectedYear = 5 < now.month ? now.year + 1 : now.year;
      expect(r.dueTime, DateTime(expectedYear, 5, 1, 18, 0));
    });
  });

  group('优先级、标签与负责人', () {
    test('紧急关键词 → 高优先级', () {
      final r = ai.parseTaskLocal('紧急修复线上bug');
      expect(r.priority, TaskPriority.high);
      expect(r.title, '修复线上bug');
    });

    test('不急关键词 → 低优先级', () {
      final r = ai.parseTaskLocal('整理文档，不急');
      expect(r.priority, TaskPriority.low);
      expect(r.title, '整理文档');
    });

    test('默认中优先级', () {
      final r = ai.parseTaskLocal('明天开会');
      expect(r.priority, TaskPriority.medium);
    });

    test('#标签 提取', () {
      final r = ai.parseTaskLocal('#工作 明天交日报');
      expect(r.tags, contains('工作'));
      expect(r.title, '交日报');
    });

    test('@负责人 提取', () {
      final r = ai.parseTaskLocal('#工作 明天交报告 @张三');
      expect(r.tags, contains('工作'));
      expect(r.assignee, '张三');
      expect(r.title, '交报告');
    });
  });

  group('推荐提醒时长收敛策略（v2.2.11）', () {
    test('12小时内 → 提前15分钟', () {
      final r = ai.parseTaskLocal('3小时后开会');
      expect(r.recommendedReminderMinutes, 15);
    });

    test('12小时内高优先级 → 提前22分钟（15×1.5）', () {
      final r = ai.parseTaskLocal('3小时后紧急开会');
      expect(r.priority, TaskPriority.high);
      expect(r.recommendedReminderMinutes, 22);
    });

    test('两天后 → 最多提前120分钟（不再有1天/2天/3天的过大提前）', () {
      final r = ai.parseTaskLocal('2天后交报告');
      expect(r.recommendedReminderMinutes, 120);
    });

    test('远期低优先级 → 96分钟（120×0.8）', () {
      final r = ai.parseTaskLocal('3天后交材料，不急');
      expect(r.priority, TaskPriority.low);
      expect(r.recommendedReminderMinutes, 96);
    });

    test('无截止时间 → 不推荐提醒', () {
      final r = ai.parseTaskLocal('开会');
      expect(r.dueTime, isNull);
      expect(r.recommendedReminderMinutes, isNull);
    });

    test('有截止时间 → 推荐提醒不为空', () {
      final r = ai.parseTaskLocal('明天开会');
      expect(r.recommendedReminderMinutes, isNotNull);
    });
  });
}
