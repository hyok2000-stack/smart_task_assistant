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
  bool _modelCopied = false;
  void Function(String finalText)? _onFinished;

  /// 模型是否已复制到本机（首次使用需大复制，UI 层可据此给提示）
  bool get offlineModelOnDevice => _modelCopied;

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
      _modelCopied = true;
      // 主 isolate 预加载原生绑定；模型本体由后台 isolate 识别时自行加载
      sherpa.initBindings();
      _offlineReady = true;
    } catch (e) {
      debugPrint('离线识别初始化失败: $e');
      _offlineReady = false;
    }
    return _offlineReady;
  }

  /// 开始离线录音（Paraformer 非流式：整段录完后由 stop 一次性识别）。
  /// [onFinished] 在录音结束（手动停止 或 静音自动断句）后回调最终文本。
  /// 返回 false 表示麦克风不可用或离线引擎未就绪。
  Future<bool> startOfflineListening({
    required void Function(String finalText) onFinished,
  }) async {
    // 模型文件须已就绪（ensureOfflineReady 负责复制）；识别在后台 isolate 进行
    if (!_offlineReady) return false;
    _onFinished = onFinished;

    _recorder = AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;

    _pcmChunks.clear();
    _pcmTotal = 0;
    _heardSpeech = false;
    _silentChunks = 0;
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

      // 静音自动断句：检测到说话后，连续静音约 1.6 秒自动结束录音并识别
      final peak = _peakAmplitude(data);
      if (peak > _speechAmplitudeThreshold) {
        _heardSpeech = true;
        _silentChunks = 0;
      } else if (_heardSpeech) {
        _silentChunks++;
        if (_silentChunks >= _silentChunksToStop) {
          _finishOfflineRecording();
          return;
        }
      } else {
        _silentChunks++;
        if (_silentChunks >= _maxSilentFromStart) {
          _finishOfflineRecording();
          return;
        }
      }
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
    if (pcm.length < 3200) {
      debugPrint('离线识别：录音过短（${pcm.length} 字节），跳过');
      return ''; // 短于 0.2 秒视为无有效输入
    }

    final rec = _offlineRecognizer;
    if (rec == null) {
      debugPrint('离线识别：引擎未初始化');
      return '';
    }
    try {
      final stream = rec.createStream();
      final samples = Float32List(pcm.length ~/ 2);
      final bd = ByteData.sublistView(pcm);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      rec.decode(stream);
      final text = rec.getResult(stream).text.trim();
      debugPrint('离线识别结果: "$text" (${pcm.length ~/ 1024}KB 音频)');
      stream.free();
      return text;
    } catch (e) {
      debugPrint('离线识别异常: $e');
      return '';
    }
  }

  // ---- 静音自动断句参数与状态 ----
  static const int _speechAmplitudeThreshold = 600; // int16 振幅阈值
  static const int _silentChunksToStop = 14; // 约 1.6 秒静音（每块 ~120ms）
  static const int _maxSilentFromStart = 40; // 从头静音约 4.5 秒自动放弃
  bool _heardSpeech = false;
  int _silentChunks = 0;

  /// 计算一段 PCM16 数据的峰值振幅
  static int _peakAmplitude(Uint8List data) {
    var peak = 0;
    final bd = ByteData.sublistView(data);
    for (var i = 0; i + 1 < data.length; i += 2) {
      final v = bd.getInt16(i * 2, Endian.little).abs();
      if (v > peak) peak = v;
    }
    return peak;
  }

  /// 结束录音 → 后台识别 → 清理，并把最终文本回调给 UI 层
  Future<void> _finishOfflineRecording() async {
    // 防重入：清掉麦克风订阅与录音器
    try {
      await _micSub?.cancel();
    } catch (_) {}
    _micSub = null;
    try {
      await _recorder?.stop();
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;

    final pcm = Uint8List(_pcmTotal);
    var off = 0;
    for (final c in _pcmChunks) {
      pcm.setAll(off, c);
      off += c.length;
    }
    _pcmChunks.clear();
    _pcmTotal = 0;
    _heardSpeech = false;
    _silentChunks = 0;

    var text = '';
    if (pcm.length >= 3200) {
      try {
        // 后台 isolate 识别：长录音的解码耗时数秒~数十秒，
        // 在主线程执行会冻结 UI 触发系统 ANR（"无响应"弹窗）
        text = await compute(_offlineRecognizeTask, {
          'pcm': pcm,
          'documentsDir': (await getApplicationDocumentsDirectory()).path,
        });
      } catch (e) {
        debugPrint('离线识别失败: $e');
      }
    }
    _onFinished?.call(text);
  }
}

/// 后台 isolate 识别任务：在独立 isolate 中创建 Paraformer 离线识别器并解码整段音频。
/// 必须是顶层函数（compute 要求）；模型在 isolate 内独立加载，与主 isolate 互不干扰。
String _offlineRecognizeTask(Map args) {
  final pcm = args['pcm'] as Uint8List;
  final modelDir = args['documentsDir'] as String;

  // 每个 isolate 有独立的 FFI 绑定状态，必须先初始化
  sherpa.initBindings();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(
          model: '$modelDir/paraformer-zh/model.int8.onnx',
        ),
        tokens: '$modelDir/paraformer-zh/tokens.txt',
        numThreads: 2,
      ),
    ),
  );
  final stream = recognizer.createStream();
  final samples = Float32List(pcm.length ~/ 2);
  final bd = ByteData.sublistView(pcm);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  stream.acceptWaveform(samples: samples, sampleRate: 16000);
  recognizer.decode(stream);
  final text = recognizer.getResult(stream).text.trim();
  stream.free();
  return text;
}
