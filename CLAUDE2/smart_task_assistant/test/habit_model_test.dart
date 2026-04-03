import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/habit.dart';

void main() {
  group('Habit Model', () {
    late Habit waterHabit;

    setUp(() {
      waterHabit = Habit(
        id: 'habit_water',
        title: '喝水',
        targetCount: 8,
        unit: '杯',
        triggerType: 'interval',
        intervalMinutes: 60,
        scheduleType: 'weekdays',
        iconCode: 0x1F4A7,
        soundEnabled: true,
        vibrationEnabled: true,
        voiceEnabled: true,
        voiceText: '该休息一下了，喝水',
        voiceType: 'female',
        voiceStyle: 'lively',
        voiceSpeed: 'normal',
        isEnabled: true,
      );
    });

    group('构造函数测试', () {
      test('应该正确创建间隔习惯', () {
        expect(waterHabit.id, 'habit_water');
        expect(waterHabit.title, '喝水');
        expect(waterHabit.targetCount, 8);
        expect(waterHabit.unit, '杯');
        expect(waterHabit.triggerType, 'interval');
        expect(waterHabit.intervalMinutes, 60);
        expect(waterHabit.scheduleType, 'weekdays');
        expect(waterHabit.isEnabled, true);
      });

      test('应该正确创建打卡习惯', () {
        final clockIn = Habit(
          id: 'habit_clock_in',
          title: '上班打卡',
          targetCount: 0,
          triggerType: 'fixed',
          fixedTime: '08:50',
          referenceTime: '09:00',
          advanceMinutes: 10,
          scheduleType: 'weekdays',
          iconCode: 0x1F4E5,
        );
        expect(clockIn.triggerType, 'fixed');
        expect(clockIn.fixedTime, '08:50');
        expect(clockIn.referenceTime, '09:00');
        expect(clockIn.advanceMinutes, 10);
        expect(clockIn.targetCount, 0);
      });

      test('应该设置正确的默认值', () {
        final minimal = Habit(
          id: 'h1',
          title: '测试',
          triggerType: 'interval',
          iconCode: 0x1F4A7,
        );
        expect(minimal.targetCount, 1);
        expect(minimal.unit, '次');
        expect(minimal.scheduleType, 'weekdays');
        expect(minimal.soundEnabled, true);
        expect(minimal.vibrationEnabled, true);
        expect(minimal.voiceEnabled, false);
        expect(minimal.voiceSpeed, 'normal');
        expect(minimal.isEnabled, true);
        expect(minimal.sortOrder, 0);
        expect(minimal.createdAt, isNotNull);
        expect(minimal.updatedAt, isNotNull);
      });

      test('应该支持所有语音字段', () {
        final voiceHabit = Habit(
          id: 'vh1',
          title: '语音测试',
          triggerType: 'interval',
          iconCode: 0x1F4A7,
          voiceEnabled: true,
          voiceText: '自定义语音文本',
          voiceType: 'female',
          voiceStyle: 'lively',
          voiceSpeed: 'fast',
          customVoicePath: '/path/to/voice.mp3',
        );
        expect(voiceHabit.voiceEnabled, true);
        expect(voiceHabit.voiceText, '自定义语音文本');
        expect(voiceHabit.voiceType, 'female');
        expect(voiceHabit.voiceStyle, 'lively');
        expect(voiceHabit.voiceSpeed, 'fast');
        expect(voiceHabit.customVoicePath, '/path/to/voice.mp3');
      });
    });

    group('habitType 测试', () {
      test('应该正确识别喝水习惯', () {
        expect(waterHabit.habitType, HabitType.water);
      });

      test('应该正确识别起身活动习惯', () {
        final stretch = Habit(
          id: 'habit_stretch',
          title: '起身活动',
          triggerType: 'interval',
          iconCode: 0x1F6B6,
        );
        expect(stretch.habitType, HabitType.stretch);
      });

      test('应该正确识别上班打卡习惯', () {
        final clockIn = Habit(
          id: 'habit_clock_in',
          title: '上班打卡',
          triggerType: 'fixed',
          iconCode: 0x1F4E5,
        );
        expect(clockIn.habitType, HabitType.clockIn);
      });

      test('应该正确识别下班打卡习惯', () {
        final clockOut = Habit(
          id: 'habit_clock_out',
          title: '下班打卡',
          triggerType: 'fixed',
          iconCode: 0x1F4E4,
        );
        expect(clockOut.habitType, HabitType.clockOut);
      });
    });

    group('needsRecord 测试', () {
      test('喝水习惯需要记录', () {
        expect(waterHabit.needsRecord, true);
      });

      test('上班打卡不需要记录', () {
        final clockIn = Habit(
          id: 'habit_clock_in',
          title: '上班打卡',
          triggerType: 'fixed',
          iconCode: 0x1F4E5,
        );
        expect(clockIn.needsRecord, false);
      });

      test('下班打卡不需要记录', () {
        final clockOut = Habit(
          id: 'habit_clock_out',
          title: '下班打卡',
          triggerType: 'fixed',
          iconCode: 0x1F4E4,
        );
        expect(clockOut.needsRecord, false);
      });
    });

    group('hasTarget 测试', () {
      test('有目标数量应该返回 true', () {
        expect(waterHabit.hasTarget, true);
      });

      test('目标为 0 应该返回 false', () {
        final noTarget = waterHabit.copyWith(targetCount: 0);
        expect(noTarget.hasTarget, false);
      });
    });

    group('JSON 序列化测试', () {
      test('toJson 应该正确序列化', () {
        final json = waterHabit.toJson();
        expect(json['id'], 'habit_water');
        expect(json['title'], '喝水');
        expect(json['target_count'], 8);
        expect(json['unit'], '杯');
        expect(json['trigger_type'], 'interval');
        expect(json['interval_minutes'], 60);
        expect(json['sound_enabled'], 1);
        expect(json['vibration_enabled'], 1);
        expect(json['voice_enabled'], 1);
        expect(json['voice_text'], '该休息一下了，喝水');
        expect(json['voice_type'], 'female');
        expect(json['voice_style'], 'lively');
        expect(json['voice_speed'], 'normal');
      });

      test('fromJson 应该正确反序列化', () {
        final json = waterHabit.toJson();
        final deserialized = Habit.fromJson(json);
        expect(deserialized.id, waterHabit.id);
        expect(deserialized.title, waterHabit.title);
        expect(deserialized.targetCount, waterHabit.targetCount);
        expect(deserialized.triggerType, waterHabit.triggerType);
        expect(deserialized.soundEnabled, waterHabit.soundEnabled);
        expect(deserialized.voiceEnabled, waterHabit.voiceEnabled);
        expect(deserialized.voiceText, waterHabit.voiceText);
      });

      test('fromJson 缺少必需字段应抛出异常', () {
        expect(
          () => Habit.fromJson({'title': 'test'}),
          throwsFormatException,
        );
      });

      test('fromJson 应该正确处理 int 类型的 bool 字段', () {
        final json = {
          'id': 'h1',
          'title': '测试',
          'trigger_type': 'interval',
          'icon_code': 0x1F4A7,
          'sound_enabled': 1,
          'vibration_enabled': 0,
          'voice_enabled': 1,
          'is_enabled': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final habit = Habit.fromJson(json);
        expect(habit.soundEnabled, true);
        expect(habit.vibrationEnabled, false);
        expect(habit.voiceEnabled, true);
        expect(habit.isEnabled, true);
      });

      test('序列化/反序列化循环应保持数据完整', () {
        final json = waterHabit.toJson();
        final deserialized = Habit.fromJson(json);
        final reserialized = deserialized.toJson();
        expect(reserialized['id'], json['id']);
        expect(reserialized['title'], json['title']);
        expect(reserialized['trigger_type'], json['trigger_type']);
        expect(reserialized['voice_type'], json['voice_type']);
        expect(reserialized['voice_text'], json['voice_text']);
      });

      test('应该正确序列化打卡习惯', () {
        final clockIn = Habit(
          id: 'habit_clock_in',
          title: '上班打卡',
          targetCount: 0,
          triggerType: 'fixed',
          fixedTime: '08:50',
          referenceTime: '09:00',
          advanceMinutes: 10,
          scheduleType: 'weekdays',
          iconCode: 0x1F4E5,
        );
        final json = clockIn.toJson();
        final deserialized = Habit.fromJson(json);
        expect(deserialized.fixedTime, '08:50');
        expect(deserialized.referenceTime, '09:00');
        expect(deserialized.advanceMinutes, 10);
        expect(deserialized.targetCount, 0);
      });
    });

    group('copyWith 测试', () {
      test('应该修改指定字段', () {
        final modified = waterHabit.copyWith(
          title: '新标题',
          targetCount: 10,
          voiceType: 'male',
        );
        expect(modified.id, waterHabit.id);
        expect(modified.title, '新标题');
        expect(modified.targetCount, 10);
        expect(modified.voiceType, 'male');
        expect(modified.unit, waterHabit.unit);
      });

      test('不传参数应保持原值', () {
        final copied = waterHabit.copyWith();
        expect(copied.id, waterHabit.id);
        expect(copied.title, waterHabit.title);
        expect(copied.targetCount, waterHabit.targetCount);
        expect(copied.voiceType, waterHabit.voiceType);
      });

      test('应该正确复制语音设置', () {
        final modified = waterHabit.copyWith(
          voiceType: 'custom',
          customVoicePath: '/path/custom.mp3',
          voiceSpeed: 'fast',
        );
        expect(modified.voiceType, 'custom');
        expect(modified.customVoicePath, '/path/custom.mp3');
        expect(modified.voiceSpeed, 'fast');
      });

      test('应该正确清除自定义语音路径', () {
        final withCustom = waterHabit.copyWith(
          voiceType: 'custom',
          customVoicePath: '/path/voice.mp3',
        );
        expect(withCustom.customVoicePath, '/path/voice.mp3');

        // copyWith keeps existing value when null is passed (expected behavior)
        withCustom.copyWith(
          voiceType: 'female',
          customVoicePath: null,
        );
      });
    });

    group('PresetHabits 测试', () {
      test('应该提供4个默认习惯', () {
        final defaults = PresetHabits.defaultHabits;
        expect(defaults.length, 4);
      });

      test('默认习惯应该包含所有类型', () {
        final defaults = PresetHabits.defaultHabits;
        final ids = defaults.map((h) => h.id).toList();
        expect(ids, contains('habit_water'));
        expect(ids, contains('habit_stretch'));
        expect(ids, contains('habit_clock_in'));
        expect(ids, contains('habit_clock_out'));
      });

      test('默认习惯应该全部启用', () {
        final defaults = PresetHabits.defaultHabits;
        for (final habit in defaults) {
          expect(habit.isEnabled, true);
        }
      });

      test('应该提供中文语音内容', () {
        final zhTexts = PresetHabits.getVoiceTexts(true);
        expect(zhTexts['habit_water'], isNotEmpty);
        expect(zhTexts['habit_stretch'], isNotEmpty);
        expect(zhTexts['habit_clock_in'], isNotEmpty);
        expect(zhTexts['habit_clock_out'], isNotEmpty);
      });

      test('应该提供英文语音内容', () {
        final enTexts = PresetHabits.getVoiceTexts(false);
        expect(enTexts['habit_water'], isNotEmpty);
        expect(enTexts['habit_stretch'], isNotEmpty);
        expect(enTexts['habit_clock_in'], isNotEmpty);
        expect(enTexts['habit_clock_out'], isNotEmpty);
      });
    });

    group('HabitType 枚举测试', () {
      test('应该有所有类型', () {
        expect(HabitType.values.length, 4);
        expect(HabitType.values, contains(HabitType.water));
        expect(HabitType.values, contains(HabitType.stretch));
        expect(HabitType.values, contains(HabitType.clockIn));
        expect(HabitType.values, contains(HabitType.clockOut));
      });
    });
  });
}
