import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音输入服务：两级识别引擎——
/// 1. 系统 ASR（speech_to_text，走 Android RecognitionService）；
/// 2. Vosk 离线识别（本地小模型，华为等无 GMS 设备的系统识别兜底）。
class SpeechInputService {
  SpeechInputService._();
  static final SpeechInputService instance = SpeechInputService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  /// 系统 ASR 是否被判定不可靠（如华为识别服务卡死：会话一直 in progress
  /// 却永远不返回结果）。置位后调用方应直接改用 Vosk 离线引擎。
  bool systemAsrUnreliable = false;

  // Vosk 离线引擎
  static const _voskChannel =
      MethodChannel('com.smarttask.smart_task_assistant/speech');
  static const _voskEvents =
      EventChannel('com.smarttask.smart_task_assistant/speech_events');
  bool _voskReady = false;
  StreamSubscription? _voskSub;

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

  // ==================== Vosk 离线识别 ====================

  /// 初始化 Vosk 离线引擎（首次会从 APK 资产解压模型，耗时数秒）。
  Future<bool> ensureVoskReady() async {
    if (_voskReady) return true;
    try {
      final ok = await _voskChannel.invokeMethod<bool>('init');
      _voskReady = ok ?? false;
    } catch (e) {
      _voskReady = false;
    }
    return _voskReady;
  }

  /// 开始 Vosk 离线聆听。
  /// [onText] 持续回传识别文本（partial + final）；
  /// [onStopped] 在停止/出错时回调（调用方复位 UI）。
  Future<void> startVoskListening({
    required void Function(String text) onText,
    void Function()? onStopped,
  }) async {
    await _voskSub?.cancel();
    _voskSub = _voskEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is! String) return;
        try {
          final map = jsonDecode(event) as Map<String, dynamic>;
          // final 结果优先（含 text 字段），否则用 partial
          final text = (map['text'] ?? map['partial'] ?? '') as String;
          if (text.trim().isNotEmpty) onText(text.trim());
        } catch (_) {
          // 非 JSON 事件忽略
        }
      },
      onDone: () => onStopped?.call(),
      onError: (_) => onStopped?.call(),
    );
    await _voskChannel.invokeMethod('start');
  }

  Future<void> stopVoskListening() async {
    try {
      await _voskChannel.invokeMethod('stop');
    } catch (_) {}
    await _voskSub?.cancel();
    _voskSub = null;
  }
}
