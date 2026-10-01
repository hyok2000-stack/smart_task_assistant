import 'package:speech_to_text/speech_to_text.dart';

/// 语音输入服务：语音转文字（设备端 ASR，中文），
/// 供快速添加弹窗 / 任务编辑把口述内容填入 AI 解析链。
class SpeechInputService {
  SpeechInputService._();
  static final instance = SpeechInputService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  bool get isListening => _speech.isListening;

  /// 初始化（幂等）。设备无可用语音识别服务时返回 false。
  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize();
    return _initialized;
  }

  /// 开始聆听。识别过程中 [onResult] 持续回传累计文本；
  /// [onFinal] 在收到最终结果（用户停止说话/超时）时回调一次。
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String finalText) onFinal,
    String localeId = 'zh_CN',
  }) async {
    await _speech.listen(
      onResult: (result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          onFinal(result.recognizedWords);
        }
      },
      localeId: localeId,
    );
  }

  Future<void> stopListening() => _speech.stop();
}
