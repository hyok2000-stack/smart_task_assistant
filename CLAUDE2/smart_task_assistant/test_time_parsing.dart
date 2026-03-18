/// 测试时间解析逻辑
import 'package:smart_task_assistant/services/ai_service.dart';

void main() {
  final aiService = AIService();

  print('当前时间测试：');
  final now = DateTime.now();
  print('当前时间: $now');
  print('当前日期: ${now.year}-${now.month}-${now.day}');

  print('\n测试：明天下午5点开会');
  final result = aiService.parseTaskLocal('明天下午5点开会');
  print('解析结果：');
  print('  标题: ${result.title}');
  print('  截止时间: ${result.dueTime}');
  print('  优先级: ${result.priority}');

  print('\n预期：明天应该是 ${now.year}-${now.month}-${now.day + 1} 17:00');
}
