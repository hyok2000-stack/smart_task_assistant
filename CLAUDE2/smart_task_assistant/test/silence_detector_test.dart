// 静音断句状态机测试：说话后 1.6 秒静音断句 / 从头 4.5 秒静音放弃
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/services/speech_input_service.dart';

void main() {
  group('SilenceDetector', () {
    test('说话后连续静音 14 块触发断句', () {
      final d = SilenceDetector();
      // 3 块说话
      for (var i = 0; i < 3; i++) {
        expect(d.shouldStop(1000), isFalse);
      }
      expect(d.heardSpeech, isTrue);
      // 静音第 1~13 块不结束
      for (var i = 1; i <= 13; i++) {
        expect(d.shouldStop(100), isFalse, reason: '静音第 $i 块不应结束');
      }
      // 第 14 块结束
      expect(d.shouldStop(100), isTrue);
    });

    test('从头静音 40 块触发放弃', () {
      final d = SilenceDetector();
      for (var i = 1; i < 40; i++) {
        expect(d.shouldStop(50), isFalse, reason: '静音第 $i 块不应放弃');
      }
      expect(d.heardSpeech, isFalse);
      expect(d.shouldStop(50), isTrue);
    });

    test('静音中再次说话会重置计数', () {
      final d = SilenceDetector();
      d.shouldStop(1000); // 说话
      for (var i = 0; i < 10; i++) {
        d.shouldStop(100); // 静音 10 块
      }
      d.shouldStop(800); // 又说话 → 计数清零
      for (var i = 1; i <= 13; i++) {
        expect(d.shouldStop(100), isFalse, reason: '重置后第 $i 块不应结束');
      }
      expect(d.shouldStop(100), isTrue);
    });

    test('峰值等于阈值不算说话（严格大于）', () {
      final d = SilenceDetector(speechThreshold: 600);
      d.shouldStop(600);
      expect(d.heardSpeech, isFalse);
    });

    test('reset 清零状态', () {
      final d = SilenceDetector();
      d.shouldStop(1000);
      for (var i = 0; i < 20; i++) {
        d.shouldStop(100); // 已触发断句
      }
      d.reset();
      expect(d.heardSpeech, isFalse);
      expect(d.silentChunks, 0);
      // 重置后从头静音需要满 40 块才放弃
      for (var i = 1; i < 40; i++) {
        expect(d.shouldStop(50), isFalse);
      }
      expect(d.shouldStop(50), isTrue);
    });

    test('默认参数换算时间：14 块≈1.6 秒，40 块≈4.5 秒', () {
      final d = SilenceDetector();
      expect(d.silenceChunksToStop, 14);
      expect(d.maxSilentChunksFromStart, 40);
      expect(d.speechThreshold, 600);
    });
  });
}
