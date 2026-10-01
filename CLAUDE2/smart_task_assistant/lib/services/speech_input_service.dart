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
    _initialized = await _speech.initialize(
      onError: (error) {
        // 识别服务出错：标记未初始化以便下次自愈，并通知监听方
        _initialized = false;
        _errorListener?.call(error.errorMsg ?? '语音识别出错');
        _stoppedCallback?.call();
      },
      onStatus: (status) {
        // 引擎停止且未给出最终结果时（异常路径），由 UI 复位状态
        if (status == 'notListening') {
          _stoppedCallback?.call();
        }
      },
    );
    return _initialized;
  }

  // 状态回调（由 UI 层在 startListening 时设置：引擎停止/出错时复位 UI）
  void Function()? _stoppedCallback;
  void Function(String message)? _errorListener;

  /// 开始聆听。识别过程中 [onResult] 持续回传累计文本；
  /// [onFinal] 在收到最终结果（用户停止说话/超时）时回调一次；
  /// [onStopped] 在引擎停止（含异常路径）时回调（调用方应复位 UI 状态）；
  /// [onError] 在识别服务出错时回调。
  Future<void> startListening({
    required void Function(String text) onResult,
    required void Function(String finalText) onFinal,
    void Function()? onStopped,
    void Function(String message)? onError,
    String localeId = 'zh_CN',
  }) async {
    _errorListener = onError;
    _stoppedCallback = onStopped;
    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
          if (result.finalResult) {
            onFinal(result.recognizedWords);
          }
        },
        localeId: localeId,
      );
    } catch (e) {
      // listen 失败（引擎刚失效等）：标记未初始化，下次调用会重新初始化
      _initialized = false;
      onError?.call('语音识别启动失败: $e');
    }
  }

  Future<void> stopListening() => _speech.stop();
}
