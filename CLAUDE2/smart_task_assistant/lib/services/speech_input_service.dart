import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:speech_to_text/speech_to_text.dart';

/// 语音输入服务：两级识别引擎——
/// 1. 系统 ASR（speech_to_text，走 Android RecognitionService）；
/// 2. sherpa-onnx 离线识别（流式 zipformer 中文小模型，完全本地）。
///
/// 系统 ASR 出现"会话卡死不出结果"等不可靠行为时，自动切换离线引擎。
class SpeechInputService {
  SpeechInputService._();
  static final SpeechInputService instance = SpeechInputService._();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;

  /// 系统 ASR 是否被判定不可靠（如华为识别服务卡死：会话一直 in progress
  /// 却永远不返回结果）。置位后调用方应直接改用离线引擎。
  bool systemAsrUnreliable = false;

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

  // ==================== 系统 ASR ====================

  // 状态回调（由 UI 层在 startListening 时设置：引擎停止/出错时复位 UI）
  void Function()? _stoppedCallback;
  void Function(String message)? _errorListener;

  /// 开始系统识别聆听。识别过程中 [onResult] 持续回传累计文本；
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

  // ==================== sherpa-onnx 离线识别 ====================

  static const _offlineAssetDir = 'assets/models/sherpa-zh14m';
  static const _offlineFiles = [
    'tokens.txt',
    'encoder-epoch-99-avg-1.int8.onnx',
    'decoder-epoch-99-avg-1.onnx',
    'joiner-epoch-99-avg-1.int8.onnx',
  ];

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  sherpa.OnlineRecognizer? _offlineRecognizer;
  sherpa.OnlineStream? _offlineStream;
  bool _offlineReady = false;

  /// 初始化离线引擎（首次把模型文件从 APK 资产复制到内部存储，秒级完成）。
  Future<bool> ensureOfflineReady() async {
    if (_offlineReady) return true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/sherpa-zh14m');
      await modelDir.create(recursive: true);
      for (final f in _offlineFiles) {
        final target = File('${modelDir.path}/$f');
        if (!target.existsSync() || target.lengthSync() == 0) {
          final data = await rootBundle.load('$_offlineAssetDir/$f');
          await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
        }
      }
      // 必须先加载原生绑定，否则所有 FFI 调用抛 "Please initialize sherpa-onnx first"
      sherpa.initBindings();
      _offlineRecognizer = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: '${modelDir.path}/encoder-epoch-99-avg-1.int8.onnx',
              decoder: '${modelDir.path}/decoder-epoch-99-avg-1.onnx',
              joiner: '${modelDir.path}/joiner-epoch-99-avg-1.int8.onnx',
            ),
            tokens: '${modelDir.path}/tokens.txt',
            numThreads: 2,
          ),
        ),
      );
      _offlineReady = true;
    } catch (e) {
      debugPrint('离线识别初始化失败: $e');
      _offlineReady = false;
    }
    return _offlineReady;
  }

  /// 开始离线聆听（16kHz PCM 麦克风流 → 流式解码）。
  /// [onText] 持续回传当前识别文本（覆盖式，直接用于输入框回显）；
  /// [onDone] 在停止聆听时回调最终文本。
  Future<bool> startOfflineListening({
    required void Function(String text) onText,
    required void Function(String finalText) onDone,
  }) async {
    final rec = _offlineRecognizer;
    if (rec == null) return false;

    _recorder = AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;

    final micStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _offlineStream = rec.createStream();
    _micSub = micStream.listen((data) {
      final stream = _offlineStream;
      if (stream == null) return;
      // PCM int16 LE → 归一化 float32
      final samples = Float32List(data.length ~/ 2);
      final bd = ByteData.sublistView(data);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      while (rec.isReady(stream)) {
        rec.decode(stream);
      }
      final text = rec.getResult(stream).text;
      if (text.trim().isNotEmpty) onText(text.trim());
    });
    return true;
  }

  /// 停止离线聆听并返回当前识别文本。
  Future<String> stopOfflineListening() async {
    try {
      await _recorder?.stop();
    } catch (_) {}
    await _micSub?.cancel();
    _micSub = null;
    var text = '';
    final stream = _offlineStream;
    final rec = _offlineRecognizer;
    if (stream != null && rec != null) {
      // 冲刺解码剩余音频后取最终文本
      while (rec.isReady(stream)) {
        rec.decode(stream);
      }
      text = rec.getResult(stream).text.trim();
    }
    _offlineStream = null;
    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
    return text;
  }
}
