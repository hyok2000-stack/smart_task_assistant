import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// 该标志持久化：一旦判定不可靠，重启后也不再尝试系统识别。
  static const _kUnreliableKey = 'system_asr_unreliable';
  bool systemAsrUnreliable = false;

  /// 启动时恢复持久化的不可靠标志（main 中调用一次）
  Future<void> loadSystemAsrUnreliable() async {
    final sp = await SharedPreferences.getInstance();
    systemAsrUnreliable = sp.getBool(_kUnreliableKey) ?? false;
  }

  /// 判定系统识别不可靠并持久化
  void markSystemAsrUnreliable() {
    systemAsrUnreliable = true;
    SharedPreferences.getInstance()
        .then((sp) => sp.setBool(_kUnreliableKey, true));
  }

  /// 重新启用系统识别（清除持久化的不可靠标志，设置页"重新启用"入口用）
  Future<void> reEnableSystemAsr() async {
    systemAsrUnreliable = false;
    _initialized = false;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUnreliableKey);
  }

  bool get isListening => _speech.isListening;

  /// 初始化（幂等）。设备无可用语音识别服务时返回 false。
  /// initialize 加超时：华为识别服务可能永久挂起（不结束、不返回、不报错），
  /// 挂起时点击麦克风会无任何反馈。
  /// 单飞：并发调用共享同一个初始化 Future——speech_to_text 插件对
  /// 重入的 initialize 会死锁（弹窗预检与点击麦克风的竞态）。
  Future<bool>? _initFuture;
  Future<bool> ensureInitialized() {
    if (_initialized) return Future.value(true);
    return _initFuture ??= _doInitialize().whenComplete(() => _initFuture = null);
  }

  Future<bool> _doInitialize() async {
    try {
      _initialized = await _speech.initialize(
        onError: (error) {
          // 识别服务出错：标记未初始化以便下次自愈，并通知监听方
          _initialized = false;
          _errorListener?.call(error.errorMsg);
          _stoppedCallback?.call();
        },
        onStatus: (status) {
          // 引擎停止且未给出最终结果时（异常路径），由 UI 复位状态
          if (status == 'notListening') {
            _stoppedCallback?.call();
          }
        },
      ).timeout(const Duration(seconds: 3));
    } catch (e) {
      // 初始化失败/超时：标记不可靠，后续直接走离线引擎
      debugPrint('系统识别初始化失败/超时: $e');
      _initialized = false;
      markSystemAsrUnreliable();
    }
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
    void Function()? onMicClosed,
  }) async {
    // 模型文件须已就绪（ensureOfflineReady 负责复制）；识别在后台 isolate 进行
    if (!_offlineReady) return false;
    _onFinished = onFinished;
    _onMicClosed = onMicClosed;

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
      // 丢弃奇数尾字节，保证 16bit 样本按 2 字节对齐
      final len = data.length & ~1;
      _pcmChunks.add(len == data.length
          ? Uint8List.fromList(data)
          : Uint8List.sublistView(data, 0, len));
      _pcmTotal += len;

      // 静音自动断句 + 实时音量给 UI（0-100）
      final peak = _peakAmplitude(data);
      _amplitudeCtrl.add((peak * 100 / 32767).round().clamp(0, 100));
      if (_silence.shouldStop(peak)) {
        _finishOfflineRecording();
        return;
      }
    });
    return true;
  }

  /// 停止录音并识别整段音频，返回最终文本（可能为空）。
  Future<String> stopOfflineListening() async {
    // 防重入：静音自动断句已在识别中 → 本次手动停止不再重复识别
    if (_offlineRecognizing) return '';
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
    if (pcm.length < 3200) {
      debugPrint('离线识别：录音过短（${pcm.length} 字节），跳过');
      return ''; // 短于 0.2 秒视为无有效输入
    }

    // 后台 isolate 识别：与静音断句路径一致，
    // 主线程解码长录音会冻结 UI 数秒~数十秒（看起来像"没反应"）
    return _recognizePcmInBackground(pcm);
  }

  /// 后台 isolate 识别 PCM，返回文本；失败或识别中异常返回空串
  Future<String> _recognizePcmInBackground(Uint8List pcm) async {
    _offlineRecognizing = true;
    final sw = Stopwatch()..start();
    try {
      final text = await compute(_offlineRecognizeTask, {
        'pcm': pcm,
        'documentsDir': (await getApplicationDocumentsDirectory()).path,
      });
      final normalized = normalizeAsrWordOrder(text);
      debugPrint(
          '离线识别结果: "$normalized" (${(pcm.length / 1024).round()}KB 音频, '
          '耗时 ${sw.elapsedMilliseconds}ms)');
      return normalized;
    } catch (e) {
      debugPrint('离线识别失败: $e');
      return '';
    } finally {
      _offlineRecognizing = false;
    }
  }

  // ---- 静音自动断句（状态机见文件末尾 SilenceDetector）----
  final SilenceDetector _silence = SilenceDetector();
  bool _offlineRecognizing = false; // isolate 识别进行中（防重入）
  void Function()? _onMicClosed;

  // 实时拾音音量（0-100），供聆听中的 UI 波形/进度显示
  final StreamController<int> _amplitudeCtrl =
      StreamController<int>.broadcast();
  Stream<int> get amplitudeStream => _amplitudeCtrl.stream;

  /// 计算一段 PCM16 数据的峰值振幅（i 为字节偏移，奇数长度截尾）
  static int _peakAmplitude(Uint8List data) {
    var peak = 0;
    final bd = ByteData.sublistView(data);
    for (var i = 0; i + 1 < data.length; i += 2) {
      final v = bd.getInt16(i, Endian.little).abs();
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

    // 麦克风已关闭：先通知 UI（切"识别中"反馈），解码在后台 isolate 进行
    _onMicClosed?.call();

    var text = '';
    if (pcm.length >= 3200) {
      text = await _recognizePcmInBackground(pcm);
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

// ============ 识别结果语序归位 ============
// Paraformer 对短句常把时间短语甩到句尾（"开会明天下午"），时间解析不受
// 影响，但标题读着别扭；把"句尾时间短语"归位到句首（"明天下午开会"）。

/// 句尾时间短语：日期（今天/明天/周X/X月X日…）+ 时段（下午/晚上…）+
/// 钟点（3点/3点半…）三者可自由组合，至少出现日期或时段
final RegExp _trailingTimePhrase = RegExp(
  r'('
  r'(?:大后天|后天|明天|今天|昨天|前天'
  r'|[本每]?(?:星期|礼拜|周)[一二三四五六日天]'
  r'|[12]?\d月[123]?\d?[日号]?|[123]?\d[日号])'
  r')?'
  r'\s*(凌晨|清晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)?'
  r'\s*((?:[01]?\d|2[0-3])[点时](?:[0-5]?\d)?分?(?:半|一刻)?)?'
  r'\s*$',
);

/// 把句尾的时间短语移到句首。仅当句尾确实是时间短语（日期或时段开头）
/// 且前面还有正文时才调整；已在句首/句中的时间不动。
String normalizeAsrWordOrder(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 4) return trimmed;
  final m = _trailingTimePhrase.firstMatch(trimmed);
  if (m == null || m.start == 0) return trimmed;
  final timePart = trimmed.substring(m.start).trim();
  // 必须含日期或时段（裸"3点"结尾如"工作到3点"不应调整）
  final hasDateOrDaypart =
      m.group(1) != null || m.group(2) != null;
  if (!hasDateOrDaypart || timePart.isEmpty) return trimmed;
  final rest = trimmed.substring(0, m.start).trim();
  if (rest.isEmpty) return trimmed;
  return '$timePart$rest';
}

/// 静音断句状态机：逐块送入峰值振幅，返回是否应结束本次录音。
/// 两种结束条件：
/// 1. 检测到说话后，连续静音 [silenceChunksToStop] 块（约 1.6 秒）→ 断句；
/// 2. 从头一直没人说话，累计 [maxSilentChunksFromStart] 块（约 4.5 秒）→ 放弃。
class SilenceDetector {
  SilenceDetector({
    this.speechThreshold = 600,
    this.silenceChunksToStop = 14,
    this.maxSilentChunksFromStart = 40,
  });

  /// int16 峰值超过此值视为说话
  final int speechThreshold;

  /// 说话后允许的连续静音块数（每块 ~120ms）
  final int silenceChunksToStop;

  /// 从头无人说话时的最大静音块数
  final int maxSilentChunksFromStart;

  bool heardSpeech = false;
  int silentChunks = 0;

  void reset() {
    heardSpeech = false;
    silentChunks = 0;
  }

  /// 送入一个音频块的峰值振幅，返回 true 表示应结束录音
  bool shouldStop(int peak) {
    if (peak > speechThreshold) {
      heardSpeech = true;
      silentChunks = 0;
      return false;
    }
    silentChunks++;
    if (heardSpeech) {
      return silentChunks >= silenceChunksToStop;
    }
    return silentChunks >= maxSilentChunksFromStart;
  }
}
