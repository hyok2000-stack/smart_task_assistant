// 识别结果语序归位测试：Paraformer 短句常把时间短语甩到句尾
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/services/speech_input_service.dart';

void main() {
  group('normalizeAsrWordOrder', () {
    test('句尾日期+时段归位到句首', () {
      expect(normalizeAsrWordOrder('开会明天下午'), '明天下午开会');
    });

    test('句尾日期+时段+钟点归位', () {
      expect(normalizeAsrWordOrder('开会明天下午3点'), '明天下午3点开会');
    });

    test('句尾周X归位', () {
      expect(normalizeAsrWordOrder('交报告周五'), '周五交报告');
    });

    test('句尾钟点带日期归位', () {
      expect(normalizeAsrWordOrder('部门会议10月8号上午9点半'), '10月8号上午9点半部门会议');
    });

    test('时间已在句首不动', () {
      expect(normalizeAsrWordOrder('明天下午开会'), '明天下午开会');
    });

    test('时间在句中不动', () {
      expect(normalizeAsrWordOrder('明天下午三点开会讨论'), '明天下午三点开会讨论');
    });

    test('裸钟点结尾不调整（工作到3点）', () {
      expect(normalizeAsrWordOrder('工作到3点'), '工作到3点');
    });

    test('无时间短语不动', () {
      expect(normalizeAsrWordOrder('写周报'), '写周报');
    });

    test('空串与短文本不动', () {
      expect(normalizeAsrWordOrder(''), '');
      expect(normalizeAsrWordOrder('开会'), '开会');
    });

    test('纯时间短语不动', () {
      expect(normalizeAsrWordOrder('明天下午'), '明天下午');
    });

    test('多字正文+句尾周天归位', () {
      expect(normalizeAsrWordOrder('陪妈妈体检星期天'), '星期天陪妈妈体检');
    });
  });
}
