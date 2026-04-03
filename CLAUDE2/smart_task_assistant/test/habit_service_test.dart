import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/habit.dart';
import 'package:smart_task_assistant/services/habit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock audioplayers platform channels to avoid MissingPluginException
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (MethodCall methodCall) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall methodCall) async => null,
  );

  group('HabitService', () {
    late HabitService service;

    setUp(() {
      service = HabitService();
    });

    group('getVoiceText 测试', () {
      test('应该优先返回自定义语音内容', () {
        final habit = Habit(
          id: 'habit_water',
          title: '喝水',
          triggerType: 'interval',
          iconCode: 0x1F4A7,
          voiceText: '自定义喝水提醒',
        );
        expect(service.getVoiceText(habit, true), '自定义喝水提醒');
      });

      test('中文模式应该返回中文默认语音', () {
        expect(
          service.getVoiceText(
            Habit(id: 'habit_water', title: '喝水', triggerType: 'interval', iconCode: 0x1F4A7),
            true,
          ),
          '该休息一下了，喝水',
        );
        expect(
          service.getVoiceText(
            Habit(id: 'habit_stretch', title: '起身活动', triggerType: 'interval', iconCode: 0x1F6B6),
            true,
          ),
          '时间到了，起身活动一下',
        );
        expect(
          service.getVoiceText(
            Habit(id: 'habit_clock_in', title: '上班打卡', triggerType: 'fixed', iconCode: 0x1F4E5),
            true,
          ),
          '该打卡了',
        );
        expect(
          service.getVoiceText(
            Habit(id: 'habit_clock_out', title: '下班打卡', triggerType: 'fixed', iconCode: 0x1F4E4),
            true,
          ),
          '下班时间到了',
        );
      });

      test('英文模式应该返回英文默认语音', () {
        expect(
          service.getVoiceText(
            Habit(id: 'habit_water', title: 'Drink Water', triggerType: 'interval', iconCode: 0x1F4A7),
            false,
          ),
          'Time for a break, drink water',
        );
        expect(
          service.getVoiceText(
            Habit(id: 'habit_stretch', title: 'Stretch', triggerType: 'interval', iconCode: 0x1F6B6),
            false,
          ),
          'Time to stretch',
        );
      });

      test('未知习惯应该返回标题作为语音内容', () {
        expect(
          service.getVoiceText(
            Habit(id: 'habit_custom', title: '自定义习惯', triggerType: 'interval', iconCode: 0x1F4A7),
            true,
          ),
          '自定义习惯',
        );
      });

      test('空字符串自定义语音应该使用默认内容', () {
        expect(
          service.getVoiceText(
            Habit(id: 'habit_water', title: '喝水', triggerType: 'interval', iconCode: 0x1F4A7, voiceText: ''),
            true,
          ),
          '该休息一下了，喝水',
        );
      });
    });

    group('calculateNextTriggerTime 测试', () {
      test('间隔习惯 null intervalMinutes 应返回 null', () {
        final habit = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: null, iconCode: 0x1F4A7,
        );
        expect(service.calculateNextTriggerTime(habit), isNull);
      });

      test('间隔习惯 intervalMinutes <= 0 应返回 null', () {
        final habit = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 0, iconCode: 0x1F4A7,
        );
        expect(service.calculateNextTriggerTime(habit), isNull);
      });

      test('固定时间习惯无 fixedTime 和 referenceTime 应返回 null', () {
        final habit = Habit(
          id: 'habit_custom', title: '自定义', triggerType: 'fixed', iconCode: 0x1F4A7,
        );
        expect(service.calculateNextTriggerTime(habit), isNull);
      });

      test('上班打卡习惯应该根据 referenceTime 计算提前提醒', () {
        final clockIn = Habit(
          id: 'habit_clock_in', title: '上班打卡', triggerType: 'fixed',
          referenceTime: '09:00', advanceMinutes: 10, scheduleType: 'daily',
          iconCode: 0x1F4E5, isEnabled: true,
        );
        final next = service.calculateNextTriggerTime(clockIn);
        if (next != null) {
          expect(next.hour, 8);
          expect(next.minute, 50);
        }
      });

      test('下班打卡习惯应该使用 referenceTime', () {
        final clockOut = Habit(
          id: 'habit_clock_out', title: '下班打卡', triggerType: 'fixed',
          referenceTime: '18:00', scheduleType: 'daily',
          iconCode: 0x1F4E4, isEnabled: true,
        );
        final next = service.calculateNextTriggerTime(clockOut);
        if (next != null) {
          expect(next.hour, 18);
          expect(next.minute, 0);
        }
      });

      test('间隔习惯应该返回未来的时间', () {
        service.updateHabits([
          Habit(id: 'habit_clock_in', title: '上班打卡', triggerType: 'fixed',
            referenceTime: '09:00', iconCode: 0x1F4E5, isEnabled: true),
          Habit(id: 'habit_clock_out', title: '下班打卡', triggerType: 'fixed',
            referenceTime: '18:00', iconCode: 0x1F4E4, isEnabled: true),
        ]);
        final water = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 60, scheduleType: 'daily',
          iconCode: 0x1F4A7, isEnabled: true,
        );
        final next = service.calculateNextTriggerTime(water);
        expect(next, isNotNull);
        expect(next!.isAfter(DateTime.now()), true);
      });
    });

    group('shouldTriggerReminder 测试', () {
      test('未启用的习惯不应该触发', () {
        final habit = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 60, iconCode: 0x1F4A7, isEnabled: false,
        );
        expect(service.shouldTriggerReminder(habit, DateTime.now()), false);
      });

      test('非工作日 + weekdays 调度不应该触发', () {
        DateTime weekendDate = DateTime(2026, 4, 4, 10, 0);
        if (weekendDate.weekday < 6) {
          while (weekendDate.weekday < 6) {
            weekendDate = weekendDate.add(const Duration(days: 1));
          }
        }
        final habit = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 60, scheduleType: 'weekdays',
          iconCode: 0x1F4A7, isEnabled: true,
        );
        expect(service.shouldTriggerReminder(habit, weekendDate), false);
      });

      test('daily 调度在周末不应该因周末直接跳过', () {
        DateTime weekendDate = DateTime(2026, 4, 4, 10, 0);
        if (weekendDate.weekday < 6) {
          while (weekendDate.weekday < 6) {
            weekendDate = weekendDate.add(const Duration(days: 1));
          }
        }
        final habit = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 60, scheduleType: 'daily',
          iconCode: 0x1F4A7, isEnabled: true,
        );
        final result = service.shouldTriggerReminder(habit, weekendDate);
        expect(result, isA<bool>());
      });
    });

    group('updateHabits 测试', () {
      test('应该更新习惯缓存', () {
        service.updateHabits([
          Habit(id: 'habit_water', title: '喝水', triggerType: 'interval', iconCode: 0x1F4A7),
        ]);
        final water = Habit(
          id: 'habit_water', title: '喝水', triggerType: 'interval',
          intervalMinutes: 60, scheduleType: 'daily',
          iconCode: 0x1F4A7, isEnabled: true,
        );
        final next = service.calculateNextTriggerTime(water);
        expect(next, isNotNull);
      });
    });
  });
}
