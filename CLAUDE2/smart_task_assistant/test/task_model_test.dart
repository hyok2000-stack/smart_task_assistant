import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/task.dart';

void main() {
  group('Task Model', () {
    late Task task;

    setUp(() {
      task = Task(
        id: 'test-task-1',
        title: '测试任务',
        content: '任务详情',
        priority: TaskPriority.medium,
        status: TaskStatus.pending,
        dueTime: DateTime(2026, 4, 5, 14, 0),
        tagIds: ['tag_work', 'tag_urgent'],
        reminderMinutes: 30,
        reminderVoiceEnabled: true,
        reminderVoiceType: 'female',
        reminderVoiceStyle: 'lively',
        reminderVoiceSpeed: 'normal',
      );
    });

    group('构造函数测试', () {
      test('应该正确创建任务', () {
        expect(task.id, 'test-task-1');
        expect(task.title, '测试任务');
        expect(task.content, '任务详情');
        expect(task.status, TaskStatus.pending);
        expect(task.priority, TaskPriority.medium);
        expect(task.dueTime, isNotNull);
        expect(task.tagIds, ['tag_work', 'tag_urgent']);
      });

      test('应该设置正确的默认值', () {
        final minimalTask = Task(id: 't1', title: '标题');
        expect(minimalTask.status, TaskStatus.pending);
        expect(minimalTask.priority, TaskPriority.medium);
        expect(minimalTask.isRecurring, false);
        expect(minimalTask.reminderDismissed, false);
        // 当前产品默认开启语音提醒；未指定声音类型时由运行时选择系统声音。
        expect(minimalTask.reminderVoiceEnabled, true);
        expect(minimalTask.reminderVoiceType, isNull);
        expect(minimalTask.reminderVoiceStyle, 'standard');
        expect(minimalTask.reminderVoiceSpeed, 'normal');
        expect(minimalTask.reminderCustomVoicePath, isNull);
        expect(minimalTask.tagIds, isEmpty);
        expect(minimalTask.attachmentPaths, isEmpty);
        expect(minimalTask.createdAt, isNotNull);
        expect(minimalTask.updatedAt, isNotNull);
      });

      test('应该支持所有语音提醒字段', () {
        final voiceTask = Task(
          id: 'vt1',
          title: '语音任务',
          reminderVoiceEnabled: true,
          reminderVoiceType: 'female',
          reminderVoiceStyle: 'lively',
          reminderVoiceSpeed: 'fast',
          reminderCustomVoicePath: '/path/to/voice.mp3',
        );
        expect(voiceTask.reminderVoiceEnabled, true);
        expect(voiceTask.reminderVoiceType, 'female');
        expect(voiceTask.reminderVoiceStyle, 'lively');
        expect(voiceTask.reminderVoiceSpeed, 'fast');
        expect(voiceTask.reminderCustomVoicePath, '/path/to/voice.mp3');
      });

      test('应该支持周期任务', () {
        final recurringTask = Task(
          id: 'rt1',
          title: '周期任务',
          isRecurring: true,
          recurringRule: 'weekly',
        );
        expect(recurringTask.isRecurring, true);
        expect(recurringTask.recurringRule, 'weekly');
      });
    });

    group('属性计算测试', () {
      test('isCompleted 应该正确判断', () {
        expect(task.isCompleted, false);
        final completed = task.copyWith(status: TaskStatus.completed);
        expect(completed.isCompleted, true);
      });

      test('isOverdue 应该在逾期时返回 true', () {
        final overdueTask = Task(
          id: 'o1',
          title: '逾期任务',
          dueTime: DateTime(2020, 1, 1),
        );
        expect(overdueTask.isOverdue, true);
      });

      test('isOverdue 不逾期时应返回 false', () {
        final futureTask = Task(
          id: 'f1',
          title: '未来任务',
          dueTime: DateTime(2099, 12, 31),
        );
        expect(futureTask.isOverdue, false);
      });

      test('isOverdue 已完成任务应返回 false', () {
        final completedOverdue = Task(
          id: 'co1',
          title: '完成但逾期',
          dueTime: DateTime(2020, 1, 1),
          status: TaskStatus.completed,
        );
        expect(completedOverdue.isOverdue, false);
      });

      test('isOverdue 没有截止时间应返回 false', () {
        final noDueTask = Task(id: 'nd1', title: '无截止时间');
        expect(noDueTask.isOverdue, false);
      });

      test('isDueToday 应该正确判断今天到期', () {
        final today = DateTime.now();
        final todayTask = Task(
          id: 'td1',
          title: '今天到期',
          dueTime: DateTime(today.year, today.month, today.day, 18, 0),
        );
        expect(todayTask.isDueToday, true);
      });

      test('isDueToday 非今天到期应返回 false', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowTask = Task(
          id: 'tm1',
          title: '明天到期',
          dueTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0),
        );
        expect(tomorrowTask.isDueToday, false);
      });

      test('isDueTomorrow 应该正确判断明天到期', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowTask = Task(
          id: 'tm2',
          title: '明天到期',
          dueTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0),
        );
        expect(tomorrowTask.isDueTomorrow, true);
      });

      test('dueTimeDescription 应该返回正确的描述', () {
        final today = DateTime.now();
        // Use a future time today to ensure it's not overdue
        final futureHour = today.hour < 23 ? today.hour + 1 : 23;
        final futureMinute = today.hour < 23 ? today.minute : 59;
        final todayTask = Task(
          id: 'td2',
          title: '今天',
          dueTime: DateTime(today.year, today.month, today.day, futureHour, futureMinute),
        );
        expect(todayTask.dueTimeDescription, contains('今天'));

        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final tomorrowTask = Task(
          id: 'tm3',
          title: '明天',
          dueTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0),
        );
        expect(tomorrowTask.dueTimeDescription, contains('明天'));
      });

      test('dueTimeDescription 没有截止时间应返回空字符串', () {
        final noDueTask = Task(id: 'nd2', title: '无截止');
        expect(noDueTask.dueTimeDescription, '');
      });
    });

    group('JSON 序列化测试', () {
      test('toJson 应该正确序列化', () {
        final json = task.toJson();
        expect(json['id'], 'test-task-1');
        expect(json['title'], '测试任务');
        expect(json['content'], '任务详情');
        expect(json['status'], TaskStatus.pending.index);
        expect(json['priority'], TaskPriority.medium.index);
        expect(json['reminder_minutes'], 30);
        // SQLite 持久化层使用 0/1 表示布尔值。
        expect(json['reminder_voice_enabled'], 1);
        expect(json['reminder_voice_type'], 'female');
        expect(json['reminder_voice_style'], 'lively');
        expect(json['reminder_voice_speed'], 'normal');
        expect(json['tag_ids'], jsonEncode(['tag_work', 'tag_urgent']));
      });

      test('fromJson 应该正确反序列化', () {
        final json = task.toJson();
        final deserialized = Task.fromJson(json);
        expect(deserialized.id, task.id);
        expect(deserialized.title, task.title);
        expect(deserialized.content, task.content);
        expect(deserialized.status, task.status);
        expect(deserialized.priority, task.priority);
        expect(deserialized.tagIds, task.tagIds);
        expect(deserialized.reminderMinutes, 30);
        expect(deserialized.reminderVoiceEnabled, true);
        expect(deserialized.reminderVoiceType, 'female');
      });

      test('fromJson 缺少必需字段应抛出异常', () {
        expect(
          () => Task.fromJson({'title': 'test'}),
          throwsFormatException,
        );
        expect(
          () => Task.fromJson({'id': '1'}),
          throwsFormatException,
        );
      });

      test('序列化/反序列化循环应保持数据完整', () {
        final json = task.toJson();
        final deserialized = Task.fromJson(json);
        final reserialized = deserialized.toJson();
        expect(reserialized['id'], json['id']);
        expect(reserialized['title'], json['title']);
        expect(reserialized['status'], json['status']);
        expect(reserialized['priority'], json['priority']);
        expect(reserialized['reminder_voice_type'], json['reminder_voice_type']);
      });

      test('fromJson 应该正确处理 int 类型的 bool 字段', () {
        final json = {
          'id': 'int-bool-test',
          'title': 'test',
          'is_recurring': 1,
          'reminder_dismissed': 0,
          'reminder_voice_enabled': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final task = Task.fromJson(json);
        expect(task.isRecurring, true);
        expect(task.reminderDismissed, false);
        expect(task.reminderVoiceEnabled, true);
      });
    });

    group('copyWith 测试', () {
      test('应该修改指定字段', () {
        final modified = task.copyWith(
          title: '新标题',
          priority: TaskPriority.high,
          status: TaskStatus.inProgress,
        );
        expect(modified.id, task.id);
        expect(modified.title, '新标题');
        expect(modified.priority, TaskPriority.high);
        expect(modified.status, TaskStatus.inProgress);
        expect(modified.content, task.content);
      });

      test('不传参数应保持原值', () {
        final copied = task.copyWith();
        expect(copied.id, task.id);
        expect(copied.title, task.title);
        expect(copied.status, task.status);
        expect(copied.priority, task.priority);
        expect(copied.tagIds, task.tagIds);
      });

      test('应该正确复制语音设置字段', () {
        final modified = task.copyWith(
          reminderVoiceType: 'male',
          reminderVoiceStyle: 'gentle',
          reminderVoiceSpeed: 'slow',
          reminderCustomVoicePath: '/new/path.wav',
        );
        expect(modified.reminderVoiceType, 'male');
        expect(modified.reminderVoiceStyle, 'gentle');
        expect(modified.reminderVoiceSpeed, 'slow');
        expect(modified.reminderCustomVoicePath, '/new/path.wav');
      });

      test('状态变更应正确设置完成时间', () {
        // pending -> completed 应该设置 completedAt
        final completed = task.copyWith(
          status: TaskStatus.completed,
          completedAt: DateTime.now(),
        );
        expect(completed.status, TaskStatus.completed);
        expect(completed.completedAt, isNotNull);
      });
    });

    group('枚举测试', () {
      test('TaskStatus 应该有正确的索引', () {
        expect(TaskStatus.pending.index, 0);
        expect(TaskStatus.inProgress.index, 1);
        expect(TaskStatus.completed.index, 2);
        expect(TaskStatus.cancelled.index, 3);
      });

      test('TaskPriority 应该有正确的索引', () {
        expect(TaskPriority.low.index, 0);
        expect(TaskPriority.medium.index, 1);
        expect(TaskPriority.high.index, 2);
      });
    });

    group('AIParsedTask 测试', () {
      test('应该正确创建 AI 解析结果', () {
        final parsed = AIParsedTask(
          title: '明天下午3点开会',
          content: '项目进度会议',
          priority: TaskPriority.high,
          assignee: '张三',
          tags: ['工作', '会议'],
        );
        expect(parsed.title, '明天下午3点开会');
        expect(parsed.content, '项目进度会议');
        expect(parsed.priority, TaskPriority.high);
        expect(parsed.assignee, '张三');
        expect(parsed.tags, ['工作', '会议']);
      });

      test('应该有正确的默认值', () {
        final parsed = AIParsedTask(title: '简单任务');
        expect(parsed.content, isNull);
        expect(parsed.priority, TaskPriority.medium);
        expect(parsed.assignee, isNull);
        expect(parsed.tags, isEmpty);
      });
    });
  });
}
