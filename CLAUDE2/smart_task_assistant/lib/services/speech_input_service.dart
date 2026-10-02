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
/// 2. sherpa-onnx 离线识别（Paraformer 中文模型，完全本地，识别质量优先）。
///
/// 系统 ASR 出现"会话卡死不出结果"等不可靠行为时，自动切换离线引擎。
/// Paraformer 为非流式模型：整段录音结束后一次性识别（中文准确率更高）。
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

  // ============ sherpa-onnx 离线识别（Paraformer 中文） ============

  static const _offlineAssetDir = 'assets/models/paraformer';
  static const _offlineModelAsset = '$_offlineAssetDir/model.int8.onnx';
  static const _offlineTokensAsset = '$_offlineAssetDir/tokens.txt';

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSub;
  final List<Uint8List> _pcmChunks = [];
  int _pcmTotal = 0;
  sherpa.OfflineRecognizer? _offlineRecognizer;
  bool _offlineReady = false;

  /// 初始化离线引擎（首次把模型文件从 APK 资产复制到内部存储）。
  Future<bool> ensureOfflineReady() async {
    if (_offlineReady) return true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${dir.path}/paraformer-zh');
      await modelDir.create(recursive: true);
      final modelFile = File('${modelDir.path}/model.int8.onnx');
      final tokensFile = File('${modelDir.path}/tokens.txt');
      if (!modelFile.existsSync() || modelFile.lengthSync() == 0) {
        final data = await rootBundle.load(_offlineModelAsset);
        await modelFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      if (!tokensFile.existsSync() || tokensFile.lengthSync() == 0) {
        final data = await rootBundle.load(_offlineTokensAsset);
        await tokensFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      // 必须先加载原生绑定，否则 FFI 调用抛 "Please initialize sherpa-onnx first"
      sherpa.initBindings();
      _offlineRecognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            paraformer: sherpa.OfflineParaformerModelConfig(
              model: modelFile.path,
            ),
            tokens: tokensFile.path,
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

  /// 开始离线录音（Paraformer 非流式：整段录完后由 stop 一次性识别）。
  /// 返回 false 表示麦克风不可用或离线引擎未就绪。
  Future<bool> startOfflineListening() async {
    final rec = _offlineRecognizer;
    if (rec == null) return false;

    _recorder = AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;

    _pcmChunks.clear();
    _pcmTotal = 0;
    final micStream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _micSub = micStream.listen((data) {
      _pcmChunks.add(Uint8List.fromList(data));
      _pcmTotal += data.length;
    });
    return true;
  }

  /// 停止录音并识别整段音频，返回最终文本（可能为空）。
  Future<String> stopOfflineListening() async {
    try {
      await _micSub?.cancel();
    } catch (_) {}
    _micSub = null;
    try {
      await _recorder?.stop();
    } catch (_) {}

    final pcm = Uint8List(_pcmTotal);
    var off = 0;
    for (final c in _pcmChunks) {
      pcm.setAll(off, c);
      off += c.length;
    }
    _pcmChunks.clear();
    _pcmTotal = 0;
    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
    if (pcm.length < 3200) return ''; // 短于 0.2 秒视为无有效输入

    final rec = _offlineRecognizer;
    if (rec == null) return '';
    final stream = rec.createStream();
    final samples = Float32List(pcm.length ~/ 2);
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    rec.decode(stream);
    final text = rec.getResult(stream).text.trim();
    stream.free();
    return text;
  }
}
