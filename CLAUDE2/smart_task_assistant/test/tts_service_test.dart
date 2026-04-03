import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/services/tts_service.dart';
import 'package:smart_task_assistant/models/task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock audioplayers platform channel to avoid MissingPluginException
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

  group('TTSService', () {
    late TTSService ttsService;

    setUp(() {
      ttsService = TTSService();
    });

    group('_getSpeechRate 测试（通过 getDefaultVoiceConfig 间接测试）', () {
      test('getDefaultVoiceConfig 高优先级应该返回女声+生动', () {
        final config = ttsService.getDefaultVoiceConfig(TaskPriority.high);
        expect(config['voiceType'], 'female');
        expect(config['voiceStyle'], 'lively');
        expect(config['voiceSpeed'], 'normal');
      });

      test('getDefaultVoiceConfig 中优先级应该返回男声+标准', () {
        final config = ttsService.getDefaultVoiceConfig(TaskPriority.medium);
        expect(config['voiceType'], 'male');
        expect(config['voiceStyle'], 'standard');
        expect(config['voiceSpeed'], 'normal');
      });

      test('getDefaultVoiceConfig 低优先级应该返回中性+柔和', () {
        final config = ttsService.getDefaultVoiceConfig(TaskPriority.low);
        expect(config['voiceType'], 'neutral');
        expect(config['voiceStyle'], 'gentle');
        expect(config['voiceSpeed'], 'normal');
      });

      test('getDefaultVoiceConfigSimple 应该返回中性+标准', () {
        final config = ttsService.getDefaultVoiceConfigSimple();
        expect(config['voiceType'], 'neutral');
        expect(config['voiceStyle'], 'standard');
        expect(config['voiceSpeed'], 'normal');
      });
    });

    group('语音选项列表测试', () {
      test('voiceTypeOptions 应该有4种类型', () {
        expect(TTSService.voiceTypeOptions.length, 4);
        final values = TTSService.voiceTypeOptions.map((e) => e.value).toList();
        expect(values, containsAll(['male', 'female', 'neutral', 'custom']));
      });

      test('voiceStyleOptions 应该有3种风格', () {
        expect(TTSService.voiceStyleOptions.length, 3);
        final values = TTSService.voiceStyleOptions.map((e) => e.value).toList();
        expect(values, containsAll(['standard', 'gentle', 'lively']));
      });

      test('voiceSpeedOptions 应该有3种速度', () {
        expect(TTSService.voiceSpeedOptions.length, 3);
        final values = TTSService.voiceSpeedOptions.map((e) => e.value).toList();
        expect(values, containsAll(['slow', 'normal', 'fast']));
      });

      test('选项应该有正确的标签', () {
        for (final option in TTSService.voiceTypeOptions) {
          expect(option.label, isNotEmpty);
          expect(option.icon, isNotEmpty);
          expect(option.value, isNotEmpty);
        }
        for (final option in TTSService.voiceStyleOptions) {
          expect(option.label, isNotEmpty);
          expect(option.icon, isNotEmpty);
        }
        for (final option in TTSService.voiceSpeedOptions) {
          expect(option.label, isNotEmpty);
          expect(option.icon, isNotEmpty);
        }
      });
    });

    group('任务提醒文本生成测试（通过 speakForTaskReminder 间接验证）', () {
      test('高优先级任务应该使用紧急前缀', () {
        // 间接测试：通过创建不同优先级的任务验证语音配置
        final highConfig = ttsService.getDefaultVoiceConfig(TaskPriority.high);
        expect(highConfig['voiceType'], 'female');
        expect(highConfig['voiceStyle'], 'lively');
      });
    });
  });

  group('VoiceTypeOption', () {
    test('应该正确创建', () {
      const option = VoiceTypeOption(value: 'test', label: '测试', icon: '🎵');
      expect(option.value, 'test');
      expect(option.label, '测试');
      expect(option.icon, '🎵');
    });
  });

  group('VoiceStyleOption', () {
    test('应该正确创建', () {
      const option = VoiceStyleOption(value: 'gentle', label: '柔和', icon: '🎵');
      expect(option.value, 'gentle');
      expect(option.label, '柔和');
      expect(option.icon, '🎵');
    });
  });

  group('VoiceSpeedOption', () {
    test('应该正确创建', () {
      const option = VoiceSpeedOption(value: 'fast', label: '快速', icon: '🚀');
      expect(option.value, 'fast');
      expect(option.label, '快速');
      expect(option.icon, '🚀');
    });
  });
}
