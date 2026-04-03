import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/task.dart';

/// TTS 服务 - 语音合成服务
/// 支持习惯提醒和任务提醒
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  // TTS 引擎
  FlutterTts? _flutterTts;
  bool _isInitialized = false;

  // 音频播放器（用于自定义语音文件）
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 当前播放模式：tts 或 custom
  String? _currentPlaybackMode;
  String? _currentCustomPath;

  // 播放完成 Completer
  Completer<void>? _playbackCompleter;
  bool _isPlaying = false;

  /// 当前是否正在播放语音
  bool get isPlaying => _isPlaying;

  // AudioPlayer 完成监听器（避免重复注册）
  StreamSubscription? _audioPlayerCompleteSubscription;

  /// 播放语音并等待完成
  Future<void> speakAndWait({
    required String text,
    String? voiceType,
    String? voiceStyle,
    String? speed,
    String? customVoicePath,
  }) async {
    // 创建新的 Completer
    _playbackCompleter = Completer<void>();
    _isPlaying = true;

    // 播放语音
    await speak(
      text: text,
      voiceType: voiceType,
      voiceStyle: voiceStyle,
      speed: speed,
      customVoicePath: customVoicePath,
    );

    // 等待播放完成
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      await _playbackCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('语音播放超时');
          _isPlaying = false;
        },
      );
    }
    _isPlaying = false;
  }

  // 可用语音列表
  List<Map<String, String>>? _availableVoices;

  // 找到的语音
  Map<String, String>? _maleVoice;
  Map<String, String>? _femaleVoice;
  Map<String, String>? _neutralVoice;

  // 初始化 TTS
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();

      // 设置共享实例，避免多个服务冲突
      await _flutterTts?.setSharedInstance(true);

      // 设置默认参数
      await _flutterTts?.setLanguage('zh-CN');
      await _flutterTts?.setSpeechRate(0.5); // 调整为更慢的语速，确保中文清晰
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);

      // 获取可用语音列表
      _availableVoices = await _flutterTts?.getVoices;
      debugPrint('可用语音数量: ${_availableVoices?.length ?? 0}');

      // 查找男声和女声
      _findVoices();

      _isInitialized = true;
      debugPrint('TTSService 初始化成功 (中文语音, 语速0.5)');
    } catch (e) {
      debugPrint('TTSService 初始化失败: $e');
    }
  }

  /// 查找可用语音
  void _findVoices() {
    if (_availableVoices == null || _availableVoices!.isEmpty) return;

    debugPrint('===== 开始查找可用语音 =====');
    debugPrint('总语音数: ${_availableVoices!.length}');

    for (var i = 0; i < _availableVoices!.length; i++) {
      final voice = _availableVoices![i];
      final name = voice['name']?.toString() ?? '';
      final locale = voice['locale']?.toString() ?? '';

      debugPrint('[$i] 语音名称: $name, 地区: $locale');

      // 只查找中文语音
      if (!locale.contains('zh') && !locale.contains('cn')) continue;

      debugPrint('  → 这是中文语音');

      // 查找男声
      if (_maleVoice == null) {
        if (name.contains('male') ||
            name.contains('男') ||
            name.contains('he') ||
            name.contains('xiaoyun') ||
            name.contains('xiaofeng') ||
            name.contains('yunjian') ||
            name.toLowerCase().contains('xiaozhi')) {  // 小智通常是男声
          _maleVoice = voice;
          debugPrint('  ✓ 找到男声: $name');
        }
      }

      // 查找女声
      if (_femaleVoice == null) {
        if (name.contains('female') ||
            name.contains('女') ||
            name.contains('she') ||
            name.contains('xiaoxin') ||
            name.contains('xiaomei') ||
            name.contains('xiaohan') ||
            name.toLowerCase().contains('xiaoya')) {  // 小雅通常是女声
          _femaleVoice = voice;
          debugPrint('  ✓ 找到女声: $name');
        }
      }

      // 查找中性语音
      if (_neutralVoice == null) {
        if (name.contains('neutral') ||
            name.contains('default') ||
            name.contains('xiaoyou') ||
            name.contains('yuxiao')) {
          _neutralVoice = voice;
          debugPrint('  ✓ 找到中性语音: $name');
        }
      }
    }

    debugPrint('===== 语音查找结果 =====');
    debugPrint('男声: ${_maleVoice?['name'] ?? "未找到"}');
    debugPrint('女声: ${_femaleVoice?['name'] ?? "未找到"}');
    debugPrint('中性: ${_neutralVoice?['name'] ?? "未找到"}');

    // 如果没有找到专用语音，使用第一个中文语音作为默认
    if (_maleVoice == null && _femaleVoice == null && _neutralVoice == null) {
      for (var voice in _availableVoices!) {
        final locale = voice['locale']?.toString() ?? '';
        if (locale.contains('zh') || locale.contains('cn')) {
          _neutralVoice = voice;
          debugPrint('使用默认中文语音: ${voice['name']}');
          break;
        }
      }
    }
  }

  /// 销化 init 方法（不含获取语音列表）
  Future<void> initSimple() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      await _flutterTts?.setSharedInstance(true);
      await _flutterTts?.setLanguage('zh-CN');
      await _flutterTts?.setSpeechRate(0.7);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
      _isInitialized = true;
    } catch (e) {
      debugPrint('TTSService 简化初始化失败: $e');
    }
  }

  /// 播报文本
  /// [text] 要播报的文本
  /// [voiceType] 语音类型：male/female/neutral/custom
  /// [voiceStyle] 语音风格：standard/gentle/lively
  /// [speed] 语速：slow/normal/fast
  /// [customVoicePath] 自定义语音文件路径
  Future<void> speak({
    required String text,
    String? voiceType,
    String? voiceStyle,
    String? speed,
    String? customVoicePath,
  }) async {
    debugPrint('===== TTSService.speak 开始 =====');
    debugPrint('文本: "$text"');
    debugPrint('语音类型: $voiceType');
    debugPrint('自定义语音路径: $customVoicePath');
    debugPrint('当前播放模式: $_currentPlaybackMode');

    // 确定本次播放模式
    final isCustomVoice = voiceType == 'custom' &&
        customVoicePath != null &&
        customVoicePath.isNotEmpty;
    final newMode = isCustomVoice ? 'custom' : 'tts';

    // 如果语音类型是 custom 但没有自定义文件，回退到 TTS 播放
    if (voiceType == 'custom' && (customVoicePath == null || customVoicePath.isEmpty)) {
      debugPrint('⚠️ 语音类型为自定义，但未提供自定义语音文件路径，回退到 TTS 播放');
      // 不 return，继续走 TTS 播放逻辑
    }

    // 始终先停止当前播放，确保新提醒能立即接管
    if (_isPlaying || _currentPlaybackMode != null) {
      debugPrint('停止当前播放，开始新播放 (模式: $_currentPlaybackMode -> $newMode)');
      await stopSpeaking();
    }

    // 使用自定义语音文件
    if (isCustomVoice) {
      _currentPlaybackMode = 'custom';
      _currentCustomPath = customVoicePath;
      debugPrint('使用自定义语音文件');
      await _playCustomVoice(customVoicePath);
      return;
    }

    // 使用 TTS 语音
    _currentPlaybackMode = 'tts';
    _currentCustomPath = null;
    debugPrint('使用 TTS 语音');

    await init();

    if (_flutterTts == null) {
      debugPrint('TTS 未初始化，无法播报');
      return;
    }

    try {
      // 停止当前播放
      await _flutterTts!.stop();

      // 确保使用中文语音
      await _flutterTts!.setLanguage('zh-CN');

      // 选择语音
      Map<String, String>? selectedVoice;
      final requestedVoiceType = voiceType ?? 'neutral';

      debugPrint('===== TTS 语音设置开始 =====');
      debugPrint('请求的语音类型: $requestedVoiceType');
      debugPrint('可用的男声: ${_maleVoice?['name']}');
      debugPrint('可用的女声: ${_femaleVoice?['name']}');
      debugPrint('可用的中性: ${_neutralVoice?['name']}');

      switch (requestedVoiceType) {
        case 'custom':
          // 自定义语音，不应该到这里（已经在上面处理了）
          debugPrint('⚠️ 不应该执行到这里：custom 类型');
          break;
        case 'male':
          selectedVoice = _maleVoice ?? _neutralVoice;
          debugPrint('选择的男声: ${selectedVoice?['name'] ?? "未找到"}');
          break;
        case 'female':
          selectedVoice = _femaleVoice ?? _neutralVoice;
          debugPrint('选择的女声: ${selectedVoice?['name'] ?? "未找到"}');
          break;
        case 'neutral':
        default:
          selectedVoice = _neutralVoice;
          debugPrint('选择的中性语音: ${selectedVoice?['name'] ?? "未找到"}');
          break;
      }

      if (selectedVoice != null) {
        debugPrint('尝试设置语音: $selectedVoice');
        try {
          await _flutterTts!.setVoice(selectedVoice);
          debugPrint('✓ 语音设置成功');
        } catch (e) {
          debugPrint('✗ 语音设置失败（设备可能不支持语音切换）: $e');
          debugPrint('将使用音调来模拟语音类型差异');
          selectedVoice = null;
        }
      }

      // 计算语速
      double speechRate = _getSpeechRate(speed ?? 'normal');
      await _flutterTts!.setSpeechRate(speechRate);

      // 计算音调（用于微调）
      double pitch = _getPitch(requestedVoiceType, voiceStyle ?? 'standard');
      await _flutterTts!.setPitch(pitch);

      debugPrint('TTS 播报参数:');
      debugPrint('  - 文本: "$text"');
      debugPrint('  - 语音: $selectedVoice');
      debugPrint('  - 语言: zh-CN');
      debugPrint('  - 语速: $speechRate');
      debugPrint('  - 音调: $pitch');
      debugPrint('===== TTS 语音设置完成 =====');

      // 设置完成回调（必须在 speak 之前设置，避免竞态条件）
      _flutterTts!.setCompletionHandler(() {
        debugPrint('TTS 播放完成');
        _isPlaying = false;
        _playbackCompleter?.complete();
      });

      // 设置错误回调
      _flutterTts!.setErrorHandler((msg) {
        debugPrint('TTS 播放错误: $msg');
        _isPlaying = false;
        _playbackCompleter?.completeError(Exception(msg));
      });

      // 播报
      var result = await _flutterTts!.speak(text);
      debugPrint('TTS speak 返回结果: $result');
    } catch (e) {
      debugPrint('TTS 播报失败: $e');
      _isPlaying = false;
      _playbackCompleter?.completeError(e);
    }
  }

  /// 播放自定义语音文件
  Future<void> _playCustomVoice(String path) async {
    try {
      // 停止当前播放
      await _audioPlayer.stop();

      // 取消之前的监听器，避免重复注册
      await _audioPlayerCompleteSubscription?.cancel();
      _audioPlayerCompleteSubscription = null;

      debugPrint('播放自定义语音文件: $path');

      // 设置完成回调（保存订阅以便后续取消）
      _audioPlayerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((event) {
        debugPrint('自定义语音播放完成');
        _isPlaying = false;
        _playbackCompleter?.complete();
      });

      await _audioPlayer.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('播放自定义语音文件失败: $e');
      _isPlaying = false;
      _playbackCompleter?.completeError(e);
    }
  }

  /// 播放自定义语音文件
  Future<void> playCustomVoice(String path) async {
    await _playCustomVoice(path);
  }

  /// 习惯专用播报
  /// [text] 要播报的文本
  /// [speed] 语速：slow/normal/fast
  Future<void> speakForHabit(String text, {String? speed}) async {
    await speak(text: text, speed: speed);
  }

  /// 任务提醒专用播报
  /// [task] 任务对象
  /// [isRepeat] 是否为重复提醒（简化语音内容）
  Future<void> speakForTaskReminder(Task task, {bool isRepeat = false}) async {
    if (!task.reminderVoiceEnabled) return;

    final text = isRepeat
        ? _getRepeatReminderText(task)
        : _getTaskReminderText(task);

    await speak(
      text: text,
      voiceType: task.reminderVoiceType,
      voiceStyle: task.reminderVoiceStyle,
      speed: task.reminderVoiceSpeed,
      customVoicePath: task.reminderCustomVoicePath,
    );
  }

  /// 获取任务提醒文本
  String _getTaskReminderText(Task task) {
    // 根据优先级选择不同的前缀
    final priorityPrefix = _getPriorityPrefix(task.priority);

    // 根据时间上下文选择不同的提醒格式
    final timeContext = _getTimeContext(task);

    return '$priorityPrefix$timeContext${task.title}';
  }

  /// 获取重复提醒文本（简化版）
  String _getRepeatReminderText(Task task) {
    // 根据优先级选择简化的提醒文本
    switch (task.priority) {
      case TaskPriority.high:
        return '紧急任务提醒';
      case TaskPriority.medium:
        return '任务提醒';
      case TaskPriority.low:
        return '温和提醒';
    }
  }

  /// 获取优先级前缀
  String _getPriorityPrefix(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return '紧急任务提醒';
      case TaskPriority.medium:
        return '任务提醒';
      case TaskPriority.low:
        return '温和提醒';
    }
  }

  /// 获取时间上下文
  String _getTimeContext(Task task) {
    if (task.dueTime == null) return '';

    final now = DateTime.now();
    final dueTime = task.dueTime!;
    final diff = dueTime.difference(now);

    if (diff.inMinutes == 0) {
      return '任务到期了，';
    } else if (diff.inMinutes > 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}分钟后需要完成，';
      } else if (diff.inHours == 1) {
        return '1小时后需要完成，';
      } else {
        return '${diff.inHours}小时后需要完成，';
      }
    }

    return '';
  }

  /// 根据语音类型和风格计算音调
  double _getPitch(String voiceType, String voiceStyle) {
    double basePitch;

    // 语音类型对音调的影响
    // 注意：不同设备的 TTS 引擎对音调的支持程度不同
    // 如果语音切换失败，会使用更大的音调差异来模拟
    switch (voiceType) {
      case 'male':
        basePitch = 0.7;  // 男声：更低的音调
        break;
      case 'female':
        basePitch = 1.3;  // 女声：更高的音调
        break;
      case 'neutral':
      default:
        basePitch = 1.0;  // 中性：标准音调
        break;
    }

    // 语音风格对音调的调整
    switch (voiceStyle) {
      case 'gentle':
        return basePitch - 0.1;
      case 'lively':
        return basePitch + 0.1;
      case 'standard':
      default:
        return basePitch;
    }
  }

  /// 根据语速选项获取语速值
  double _getSpeechRate(String speed) {
    switch (speed) {
      case 'slow':
        return 0.4;  // 慢速
      case 'normal':
        return 0.5;  // 正常（进一步降低）
      case 'fast':
        return 0.7;  // 快速（进一步降低）
      default:
        return 0.5;
    }
  }

  /// 停止语音播报
  Future<void> stopSpeaking() async {
    debugPrint('TTSService 停止播放');
    if (_flutterTts != null) {
      try {
        await _flutterTts!.stop();
        debugPrint('TTS 已停止');
      } catch (e) {
        debugPrint('TTS 停止失败: $e');
      }
    }
    // 同时停止音频播放器
    try {
      await _audioPlayer.stop();
      debugPrint('音频播放器已停止');
    } catch (e) {
      debugPrint('音频播放器停止失败: $e');
    }
    // 重置播放状态
    _isPlaying = false;
    _currentPlaybackMode = null;
    _currentCustomPath = null;
    // 完成 Completer，解除 speakAndWait 的等待
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
  }

  /// 测试语音（如果正在播放则停止，否则开始播放）
  /// [text] 测试文本
  /// [voiceType] 语音类型
  /// [voiceStyle] 语音风格
  /// [speed] 语速
  /// [customVoicePath] 自定义语音文件路径
  /// 返回 true 表示开始播放，false 表示停止播放
  Future<bool> testVoice({
    String text = '测试语音',
    String? voiceType,
    String? voiceStyle,
    String? speed,
    String? customVoicePath,
  }) async {
    if (_isPlaying) {
      await stopSpeaking();
      return false;
    }
    await speakAndWait(
      text: text,
      voiceType: voiceType,
      voiceStyle: voiceStyle,
      speed: speed,
      customVoicePath: customVoicePath,
    );
    return true;
  }

  /// 测试任务提醒语音
  Future<void> testTaskReminder({
    required String title,
    TaskPriority priority = TaskPriority.medium,
    String? voiceType,
    String? voiceStyle,
    String? speed,
    required int reminderMinutes,
  }) async {
    final now = DateTime.now();
    final dueTime = now.add(Duration(minutes: reminderMinutes));

    final testTask = Task(
      id: 'test',
      title: title,
      priority: priority,
      dueTime: dueTime,
      reminderVoiceEnabled: true,
      reminderVoiceType: voiceType,
      reminderVoiceStyle: voiceStyle,
      reminderVoiceSpeed: speed,
    );

    await speakForTaskReminder(testTask);
    await Future.delayed(const Duration(seconds: 3));
    await stopSpeaking();
  }

  /// 获取默认语音配置（根据任务优先级）
  Map<String, String?> getDefaultVoiceConfig(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return {
          'voiceType': 'female',
          'voiceStyle': 'lively',
          'voiceSpeed': 'normal',
        };
      case TaskPriority.medium:
        return {
          'voiceType': 'male',
          'voiceStyle': 'standard',
          'voiceSpeed': 'normal',
        };
      case TaskPriority.low:
        return {
          'voiceType': 'neutral',
          'voiceStyle': 'gentle',
          'voiceSpeed': 'normal',
        };
    }
  }

  /// 销化语音配置（不带任务优先级）
  Map<String, String?> getDefaultVoiceConfigSimple() {
    return {
      'voiceType': 'neutral',
      'voiceStyle': 'standard',
      'voiceSpeed': 'normal',
    };
  }

  /// 语音类型选项列表
  static const List<VoiceTypeOption> voiceTypeOptions = [
    VoiceTypeOption(value: 'male', label: '男声', icon: '👨'),
    VoiceTypeOption(value: 'female', label: '女声', icon: '👩'),
    VoiceTypeOption(value: 'neutral', label: '中性', icon: '⚖️'),
    VoiceTypeOption(value: 'custom', label: '自定义', icon: '📁'),
  ];

  /// 语音风格选项列表
  static const List<VoiceStyleOption> voiceStyleOptions = [
    VoiceStyleOption(value: 'standard', label: '标准', icon: '📢'),
    VoiceStyleOption(value: 'gentle', label: '柔和', icon: '🎵'),
    VoiceStyleOption(value: 'lively', label: '生动', icon: '🎶'),
  ];

  /// 语速选项列表
  static const List<VoiceSpeedOption> voiceSpeedOptions = [
    VoiceSpeedOption(value: 'slow', label: '慢速', icon: '🐢'),
    VoiceSpeedOption(value: 'normal', label: '正常', icon: '🚶'),
    VoiceSpeedOption(value: 'fast', label: '快速', icon: '🚀'),
  ];
}

/// 语音类型选项
class VoiceTypeOption {
  final String value;
  final String label;
  final String icon;

  const VoiceTypeOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// 语音风格选项
class VoiceStyleOption {
  final String value;
  final String label;
  final String icon;

  const VoiceStyleOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// 语速选项
class VoiceSpeedOption {
  final String value;
  final String label;
  final String icon;

  const VoiceSpeedOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}