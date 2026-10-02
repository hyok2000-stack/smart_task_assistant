import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/task_suggestion.dart';
import 'secure_storage_service.dart';

/// AI聊天结果
class ChatResult {
  final String content;
  final String engineType; // 'local' 或 AI模型名称
  final bool isFromAI;

  ChatResult({
    required this.content,
    required this.engineType,
    required this.isFromAI,
  });
}

/// AI 服务配置
class AIConfig {
  static const _configSentinel = Object();

  final String provider;
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool enabled;

  AIConfig({
    this.provider = 'local',
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.enabled = false,
  });

  AIConfig copyWith({
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    Object? enabled = _configSentinel,
  }) {
    return AIConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: identical(enabled, _configSentinel) ? this.enabled : enabled as bool,
    );
  }

  /// 序列化为 JSON 用于持久化。
  ///
  /// 注意：出于安全考虑，[apiKey] **不写入** 持久化的 JSON，
  /// 改由 [AIService] 单独存入 SecureStorage（见 [AIService._apiKeySecureKey]）。
  /// 内存中的 [AIConfig.apiKey] 仍正常用于运行时 HTTP 请求。
  Map<String, dynamic> toJson() => {
        'provider': provider,
        'baseUrl': baseUrl,
        'model': model,
        'enabled': enabled,
      };

  factory AIConfig.fromJson(Map<String, dynamic> json) {
    return AIConfig(
      provider: json['provider'] ?? 'local',
      // 兼容旧版本：旧 JSON 中可能残留 apiKey，读取后由 AIService 迁移到 SecureStorage
      apiKey: json['apiKey'] ?? '',
      baseUrl: json['baseUrl'] ?? '',
      model: json['model'] ?? '',
      enabled: json['enabled'] ?? false,
    );
  }
}

/// AI 任务解析结果
class ParsedTask {
  final String title;
  final String? content;
  final DateTime? dueTime;
  final TaskPriority priority;
  final String? assignee;
  final List<String> tags;
  final int? recommendedReminderMinutes; // 推荐的提醒分钟数

  ParsedTask({
    required this.title,
    this.content,
    this.dueTime,
    this.priority = TaskPriority.medium,
    this.assignee,
    this.tags = const [],
    this.recommendedReminderMinutes,
  });
}

/// AI 服务（单例模式）
class AIService {
  static const String _configKey = 'ai_config';
  // apiKey 在 SecureStorage 中的独立键名（不再写入 SharedPreferences）
  static const String _apiKeySecureKey = 'ai_service.apiKey';
  // 迁移标记：把旧版 ai_config JSON 中残留的明文 apiKey 迁走
  static const String _aiJsonMigratedKey = 'ai_config_apikey_migrated_v1';
  static final AIService _instance = AIService._internal();

  factory AIService() => _instance;

  AIService._internal();

  AIConfig _config = AIConfig();
  bool _configLoaded = false;

  AIConfig get config => _config;

  /// 加载配置
  Future<void> loadConfig({bool forceReload = false}) async {
    if (!forceReload && _configLoaded) {
      debugPrint(
          'AI配置已加载: enabled=${_config.enabled}, provider=${_config.provider}');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);
      if (configJson != null) {
        _config = AIConfig.fromJson(jsonDecode(configJson));

        // 一次性迁移：若旧 JSON 中残留了明文 apiKey，迁到 SecureStorage 后清空内存字段，
        // 避免明文继续留在 prefs 的 ai_config 中
        if (prefs.getBool(_aiJsonMigratedKey) != true && _config.apiKey.isNotEmpty) {
          await SecureStorageService.instance
              .write(_apiKeySecureKey, _config.apiKey);
          await prefs.setBool(_aiJsonMigratedKey, true);
          debugPrint('已将 ai_config 中的明文 apiKey 迁移至 SecureStorage');
        }
        _config = _config.copyWith(
            apiKey: ''); // 清空内存中的 apiKey，下方从安全存储重新读取
        debugPrint(
            'AI配置加载成功: enabled=${_config.enabled}, provider=${_config.provider}, baseUrl=${_config.baseUrl}');
      }

      // 从安全存储读取 apiKey 合并到内存配置
      final secureApiKey =
          await SecureStorageService.instance.read(_apiKeySecureKey);
      if (secureApiKey != null && secureApiKey.isNotEmpty) {
        _config = _config.copyWith(apiKey: secureApiKey);
      }

      _configLoaded = true;
    } catch (e) {
      debugPrint('加载 AI 配置失败: $e');
    }
  }

  /// 保存配置
  ///
  /// 安全改进：apiKey 单独存入 SecureStorage，不再混入 SharedPreferences 的 JSON。
  Future<void> saveConfig() async {
    try {
      // apiKey 走安全存储
      await SecureStorageService.instance
          .write(_apiKeySecureKey, _config.apiKey);
      // 其余字段（toJson 已不含 apiKey）写入 prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('保存 AI 配置失败: $e');
    }
  }

  /// 更新配置
  Future<void> updateConfig(AIConfig newConfig) async {
    _config = newConfig;
    _configLoaded = true; // 标记配置已加载
    await saveConfig();
    debugPrint(
        'AI配置已更新: enabled=${_config.enabled}, provider=${_config.provider}, baseUrl=${_config.baseUrl}');
  }

  /// 使用本地规则解析（公开方法，用于默认解析）
  ParsedTask parseTaskLocal(String input) {
    return _parseWithRules(input);
  }

  /// 解析阿拉伯数字或汉字数字（语音识别常输出汉字："四点""三个小时后"）。
  /// 支持 一~九、两、十、十X、X十、X十X；失败返回 null。
  static int? _cnOrDigitToInt(String s) {
    const d = {
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (s.length == 1) {
      if (s == '十') return 10;
      return d[s] ?? int.tryParse(s);
    }
    final tenIdx = s.indexOf('十');
    if (tenIdx >= 0) {
      final tens = tenIdx == 0 ? 1 : (d[s.substring(0, tenIdx)] ?? 0);
      final rest = s.substring(tenIdx + 1);
      final ones = rest.isEmpty ? 0 : (d[rest] ?? 0);
      return tens * 10 + ones;
    }
    return int.tryParse(s);
  }

  /// 解析自然语言任务
  Future<ParsedTask?> parseTask(String input) async {
    if (input.trim().isEmpty) return null;

    // 如果 AI 未启用，使用本地规则引擎
    if (!_config.enabled) {
      return _parseWithRules(input);
    }

    // 使用 AI 服务解析
    try {
      return await _parseWithAI(input);
    } catch (e) {
      debugPrint('AI 解析失败: $e');
      // AI 失败时回退到规则引擎
      return _parseWithRules(input);
    }
  }

  /// 本地规则引擎解析
  ParsedTask _parseWithRules(String input) {
    String title = input;
    DateTime? dueTime;
    TaskPriority priority = TaskPriority.medium;
    String? assignee;
    List<String> tags = [];

    // 时间关键词，不应作为标签
    final timeKeywords = [
      '今天',
      '今日',
      '明天',
      '后天',
      '大后天',
      '下周',
      '本周',
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
      '周天',
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
      '星期天',
      '上午',
      '下午',
      '晚上',
      '中午',
      '早上',
      '早晨',
      '晚间'
    ];

    // 提取标签 #工作 #个人 等
    final tagRegex = RegExp(r'#(\S+)');
    final tagMatches = tagRegex.allMatches(input);
    for (final match in tagMatches) {
      final tag = match.group(1)!;
      // 排除时间关键词作为标签
      if (!timeKeywords.contains(tag)) {
        tags.add(tag);
      }
    }
    title = title.replaceAll(tagRegex, '').trim();

    // 提取负责人 @某人 或 "由XX负责"
    final assigneeRegex1 = RegExp(r'@(\S+)');
    final assigneeRegex2 = RegExp(r'由(\S+)负责');
    final assigneeMatch =
        assigneeRegex1.firstMatch(input) ?? assigneeRegex2.firstMatch(input);
    if (assigneeMatch != null) {
      assignee = assigneeMatch.group(1);
      title = title
          .replaceAll(assigneeRegex1, '')
          .replaceAll(assigneeRegex2, '')
          .trim();
    }

    // 识别优先级关键词
    // 注意："不急"包含"急"字，低优先级必须先判断，否则永远命中"急"的高优先级分支
    if (title.contains('不急') ||
        title.contains('有空') ||
        title.contains('闲暇')) {
      priority = TaskPriority.low;
      title = title.replaceAll(RegExp(r'(不急|有空|闲暇)'), '').trim();
    } else if (title.contains('紧急') ||
        title.contains('重要') ||
        title.contains('急') ||
        title.contains('尽快')) {
      priority = TaskPriority.high;
      title = title.replaceAll(RegExp(r'(紧急|重要|急|尽快)'), '').trim();
    }

    // 识别时间
    final now = DateTime.now();

    // 今天/明天/后天
    if (title.contains('今天') || title.contains('今日')) {
      dueTime = DateTime(now.year, now.month, now.day, 18, 0);
      title = title.replaceAll(RegExp(r'(今天|今日)'), '').trim();
    } else if (title.contains('明天')) {
      dueTime = DateTime(now.year, now.month, now.day + 1, 18, 0);
      title = title.replaceAll('明天', '').trim();
    } else if (title.contains('后天')) {
      dueTime = DateTime(now.year, now.month, now.day + 2, 18, 0);
      title = title.replaceAll('后天', '').trim();
    }
    // 下周几
    else if (title.contains('下周')) {
      final weekdayMatch = RegExp(r'下周([一二三四五六七日天])').firstMatch(title);
      if (weekdayMatch != null) {
        final weekdayMap = {
          '一': 1,
          '二': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '七': 7,
          '日': 7,
          '天': 7,
        };
        final targetWeekday = weekdayMap[weekdayMatch.group(1)] ?? 1;
        final daysUntilNextWeek = 7 - now.weekday + targetWeekday;
        dueTime =
            DateTime(now.year, now.month, now.day + daysUntilNextWeek, 18, 0);
        title = title.replaceAll(weekdayMatch.group(0)!, '').trim();
      }
      title = title.replaceAll('下周', '').trim();
    }
    // 本周几
    else if (title.contains('本周')) {
      final weekdayMatch = RegExp(r'本周([一二三四五六七日天])').firstMatch(title);
      if (weekdayMatch != null) {
        final weekdayMap = {
          '一': 1,
          '二': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '七': 7,
          '日': 7,
          '天': 7,
        };
        final targetWeekday = weekdayMap[weekdayMatch.group(1)] ?? 1;
        var daysUntil = targetWeekday - now.weekday;
        if (daysUntil <= 0) daysUntil += 7; // 如果已过，则为下周
        dueTime = DateTime(now.year, now.month, now.day + daysUntil, 18, 0);
        title = title.replaceAll(weekdayMatch.group(0)!, '').trim();
      }
      title = title.replaceAll('本周', '').trim();
    }
    // 周几（默认本周）
    else {
      final weekdayMatch = RegExp(r'[周星期]([一二三四五六七日天])').firstMatch(title);
      if (weekdayMatch != null) {
        final weekdayMap = {
          '一': 1,
          '二': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '七': 7,
          '日': 7,
          '天': 7,
        };
        final targetWeekday = weekdayMap[weekdayMatch.group(1)] ?? 1;
        var daysUntil = targetWeekday - now.weekday;
        if (daysUntil < 0) daysUntil += 7;
        dueTime = DateTime(now.year, now.month, now.day + daysUntil, 18, 0);
        title = title.replaceAll(weekdayMatch.group(0)!, '').trim();
      }
    }

    // 识别具体日期：X月X日
    final dateRegex = RegExp(r'(\d{1,2})月(\d{1,2})[日号]');
    final dateMatch = dateRegex.firstMatch(title);
    if (dateMatch != null) {
      final month = int.tryParse(dateMatch.group(1)!) ?? now.month;
      final day = int.tryParse(dateMatch.group(2)!) ?? now.day;
      var year = now.year;
      // 明年关键词优先；否则月份已过则进位到明年（注意 month==now.month 不进位，避免"今年本月"误判明年）
      final isNextYear = title.contains('明年') || title.contains('下一年') || title.contains('下年');
      if (isNextYear) {
        year = now.year + 1;
      } else if (month < now.month) {
        year++;
      }
      dueTime =
          DateTime(year, month, day, dueTime?.hour ?? 18, dueTime?.minute ?? 0);
      title = title.replaceAll(dateRegex, '').trim();
    }

    // 记录时段标志，用于调整小时数
    bool isAfternoon = false;
    bool isMorning = false;
    bool isEvening = false;
    bool isNoon = false;

    // 先识别时段标志（在时间识别之前）
    if (title.contains('上午') || title.contains('早上') || title.contains('早晨')) {
      isMorning = true;
      title = title.replaceAll(RegExp(r'(上午|早上|早晨)'), '').trim();
    } else if (title.contains('中午')) {
      isNoon = true;
      title = title.replaceAll('中午', '').trim();
    } else if (title.contains('下午')) {
      isAfternoon = true;
      title = title.replaceAll('下午', '').trim();
    } else if (title.contains('晚上') || title.contains('晚间')) {
      isEvening = true;
      title = title.replaceAll(RegExp(r'(晚上|晚间)'), '').trim();
    }

    // 先识别"X小时后"和"X天后"——这些必须在 timeRegex 之前处理，
    // 否则 timeRegex 的 [:点] 会错误匹配 "3小时" 中的 "3时"。
    // 注意：timeRegex 的字符类已移除"时"字，只匹配 : 和 点。
    bool isRelativeTime = false; // 标记是否已通过相对时间设置 dueTime

    // 识别X天后（支持汉字数字：两天后/三天后——语音识别常输出汉字）
    final daysAfterRegex = RegExp(r'(\d+|[一二两三四五六七八九十]{1,3})天后');
    final daysAfterMatch = daysAfterRegex.firstMatch(title);
    if (daysAfterMatch != null) {
      final days = _cnOrDigitToInt(daysAfterMatch.group(1)!) ?? 1;
      dueTime = DateTime(now.year, now.month, now.day + days, 18, 0);
      title = title.replaceAll(daysAfterRegex, '').trim();
      isRelativeTime = true;
    }

    // 识别X小时后（同样支持汉字数字：三个小时后）
    final hoursAfterRegex = RegExp(r'(\d+|[一二两三四五六七八九十]{1,3})个?小时后');
    final hoursAfterMatch = hoursAfterRegex.firstMatch(title);
    if (hoursAfterMatch != null) {
      final hours = _cnOrDigitToInt(hoursAfterMatch.group(1)!) ?? 1;
      dueTime = now.add(Duration(hours: hours));
      title = title.replaceAll(hoursAfterRegex, '').trim();
      isRelativeTime = true;
    }

    // 识别具体时间 HH:mm 或 X点X分 或 汉字数字（四点/十点半——语音识别常输出汉字）
    // 字符类只含 : 和 点，不含"时"——避免"3小时"被误匹配
    final timeRegex = RegExp(r'(\d{1,2}|[一二两三四五六七八九十]{1,3})[:点](半|\d{0,2})?分?');
    final timeMatch = timeRegex.firstMatch(title);
    if (timeMatch != null) {
      var hour = _cnOrDigitToInt(timeMatch.group(1)!) ?? 18;
      final minuteRaw = timeMatch.group(2);
      final minute = minuteRaw == '半' ? 30 : (int.tryParse(minuteRaw ?? '') ?? 0);

      // 根据时段调整小时数
      if (isAfternoon && hour >= 1 && hour <= 11) {
        hour += 12; // 下午X点 → X+12（如下午3点→15点）
      } else if (isMorning && hour == 12) {
        hour = 0; // 上午12点 → 0点
      } else if (isNoon && hour != 12) {
        hour = 12;
      } else if (isEvening) {
        if (hour == 12) {
          hour = 0; // 晚上12点 → 0点
        } else if (hour >= 1 && hour <= 11) {
          hour += 12; // 晚上7点 → 19点
        }
        // hour 为 0-5 的时间（凌晨）不调整
      }

      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        if (dueTime != null) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, hour, minute);
        } else {
          dueTime = DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
      title = title.replaceAll(timeRegex, '').trim();
    } else if (!isRelativeTime) {
      // 没有具体时间且不是相对时间（如"X小时后"），根据时段设置默认时间
      // 如果 isRelativeTime=true（已通过"X小时后"设置了 dueTime），跳过此分支避免覆盖
      if (dueTime != null) {
        if (isMorning) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 9, 0);
        } else if (isNoon) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 12, 0);
        } else if (isAfternoon) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 15, 0);
        } else if (isEvening) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 20, 0);
        }
      }
    }

    // 清理多余空格和标点
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'[，。！？、]'), '').trim();

    // 智能推荐提醒时间
    final recommendedReminderMinutes =
        _calculateRecommendedReminder(dueTime, priority);

    return ParsedTask(
      title: title.isNotEmpty ? title : input,
      dueTime: dueTime,
      priority: priority,
      assignee: assignee,
      tags: tags,
      recommendedReminderMinutes: recommendedReminderMinutes,
    );
  }

  /// 根据截止时间和优先级计算推荐的提醒时间
  int? _calculateRecommendedReminder(DateTime? dueTime, TaskPriority priority) {
    if (dueTime == null) return null;

    final now = DateTime.now();
    final hoursUntilDue = dueTime.difference(now).inHours;

    // 如果时间已经过去，不推荐提醒
    if (hoursUntilDue <= 0) return null;

    int baseReminderMinutes;

    // 根据时间距离计算基础提醒时间（收敛策略：远期任务也不提前太多，
    // 否则"后天3点"的任务在"明天3点"就响铃，用户会觉得莫名其妙）
    if (hoursUntilDue < 12) {
      // 今天内：提前15分钟
      baseReminderMinutes = 15;
    } else if (hoursUntilDue < 24) {
      // 明天：提前1小时
      baseReminderMinutes = 60;
    } else {
      // 更远（后天及以后）：提前2小时，保持合理的提醒节奏
      baseReminderMinutes = 120;
    }

    // 根据优先级调整
    switch (priority) {
      case TaskPriority.high:
        // 高优先级：提前更多（1.5倍）
        return (baseReminderMinutes * 1.5).toInt();
      case TaskPriority.low:
        // 低优先级：提前较少（0.8倍）
        return (baseReminderMinutes * 0.8).toInt();
      default:
        return baseReminderMinutes;
    }
  }

  /// 使用 AI 服务解析
  Future<ParsedTask?> _parseWithAI(String input) async {
    if (_config.apiKey.isEmpty || _config.baseUrl.isEmpty) {
      return _parseWithRules(input);
    }

    final now = DateTime.now();
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
    final nowStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final prompt = '''
请从以下文本中提取任务信息，重点识别：
1. **任务标题**（必需）：简明扼要地总结任务内容
2. **截止时间**（必需）：识别日期和时间，格式为 YYYY-MM-DD HH:mm
3. **优先级**（必需）：根据紧急程度判断，high（高）/medium（中）/low（低）

返回 JSON 格式：
{
  "title": "任务标题",
  "dueTime": "YYYY-MM-DD HH:mm",
  "priority": "high/medium/low",
  "content": "任务详情（可选）",
  "assignee": "负责人（可选）",
  "tags": ["标签1", "标签2"]
}

文本：${_sanitizeForPrompt(input)}

要求：
- title、dueTime、priority 三个字段必须有值
- 当前时间是 $nowStr（星期$weekday）。所有日期必须以当前时间为基准换算，
  原文没写年份的一律使用当前年份；相对表述（明天/下周X/N天后）按当前时间推算
- 时间格式必须严格遵循 YYYY-MM-DD HH:mm（如：2026-03-19 15:30）
- 只返回 JSON，不要其他内容
''';

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 120);

      final response = await dio.post(
        '${_config.baseUrl}/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_config.apiKey}',
          },
        ),
        data: {
          'model': _config.model,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.3,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final content = data['choices'][0]['message']['content'] as String;

        // 提取 JSON
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
        if (jsonMatch != null) {
          final json = jsonDecode(jsonMatch.group(0)!);
          var dueTime =
              json['dueTime'] != null ? DateTime.tryParse(json['dueTime']) : null;
          dueTime = _reanchorStaleYear(dueTime, input, now);
          debugPrint('AI 解析成功: title=${json['title']}, '
              'dueTime=${dueTime?.toString()}, priority=${json['priority']}');
          return ParsedTask(
            title: json['title'] ?? input,
            content: json['content'],
            dueTime: dueTime,
            priority: _parsePriority(json['priority']),
            assignee: json['assignee'],
            tags: List<String>.from(json['tags'] ?? []),
          );
        }
      }
    } catch (e) {
      debugPrint('AI API 调用失败: $e');
      // 连接失败时自动切换回本地规则引擎
      _fallbackToRules();
      return _parseWithRules(input);
    }

    return _parseWithRules(input);
  }

  /// 回退到本地规则引擎（仅本次降级，不修改持久化配置）
  void _fallbackToRules() {
    debugPrint('AI 服务本次调用失败，临时降级到本地规则引擎');
  }

  /// AI 模型可能猜错年份（如把「9月12日」解析成往年，导致任务一创建就逾期）。
  /// 若返回的日期已过去、年份与当前不同、且原文没有写明该年份，
  /// 则把年份校正为当前年份。
  DateTime? _reanchorStaleYear(DateTime? dueTime, String input, DateTime now) {
    if (dueTime == null) return null;
    if (dueTime.isBefore(now) &&
        dueTime.year != now.year &&
        !input.contains(dueTime.year.toString())) {
      final fixed = DateTime(
          now.year, dueTime.month, dueTime.day, dueTime.hour, dueTime.minute);
      debugPrint('AI 返回 ${dueTime.year} 年的过期日期，已校正为 $fixed');
      return fixed;
    }
    return dueTime;
  }

  TaskPriority _parsePriority(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
      case '高':
        return TaskPriority.high;
      case 'low':
      case '低':
        return TaskPriority.low;
      default:
        return TaskPriority.medium;
    }
  }

  /// C9: 根据标题和内容建议优先级和截止时间
  Map<String, dynamic> suggestMetadata(String title, [String? content]) {
    TaskPriority suggestedPriority = TaskPriority.medium;
    DateTime? suggestedDueTime;
    String reason = '';

    final text = '$title ${content ?? ''}'.toLowerCase();

    // 高优先级关键词
    if (text.contains('紧急') || text.contains('马上') || text.contains('立即') || text.contains('尽快') || text.contains('urgent')) {
      suggestedPriority = TaskPriority.high;
      reason = '包含紧急关键词';
    } else if (text.contains('重要') || text.contains('必须') || text.contains('关键') || text.contains('critical')) {
      suggestedPriority = TaskPriority.high;
      reason = '包含重要性关键词';
    } else if (text.contains('低') && (text.contains('优先') || text.contains('不重要'))) {
      suggestedPriority = TaskPriority.low;
      reason = '包含低优先级关键词';
    }

    // 截止时间建议
    final now = DateTime.now();
    if (text.contains('会议') || text.contains('开会')) {
      suggestedDueTime = DateTime(now.year, now.month, now.day, 17, 0);
      if (reason.isNotEmpty) reason += '；';
      reason += '会议类任务建议今天下班前';
    } else if (text.contains('修复') || text.contains('bug') || text.contains('故障')) {
      suggestedDueTime = now.add(const Duration(hours: 4));
      if (reason.isNotEmpty) reason += '；';
      reason += '修复类任务建议4小时内';
    } else if (text.contains('报告') || text.contains('总结') || text.contains('周报')) {
      suggestedDueTime = now.add(const Duration(days: 1));
      if (reason.isNotEmpty) reason += '；';
      reason += '报告类任务建议明天完成';
    }

    return {
      'suggestedPriority': suggestedPriority,
      'suggestedDueTime': suggestedDueTime,
      'reason': reason,
    };
  }

  /// 生成任务优先级建议
  Future<TaskPrioritySuggestion> generatePrioritySuggestion(
      List<Task> tasks) async {
    if (!_config.enabled || _config.apiKey.isEmpty || _config.baseUrl.isEmpty) {
      return _generateLocalPrioritySuggestion(tasks);
    }

    try {
      return await _generateAIPrioritySuggestion(tasks);
    } catch (e) {
      debugPrint('AI 生成优先级建议失败: $e');
      // AI 失败时回退到本地规则
      return _generateLocalPrioritySuggestion(tasks);
    }
  }

  /// 使用 AI 生成优先级建议
  Future<TaskPrioritySuggestion> _generateAIPrioritySuggestion(
      List<Task> tasks) async {
    // 过滤未完成的任务
    final uncompletedTasks = tasks.where((t) => !t.isCompleted).toList();

    if (uncompletedTasks.isEmpty) {
      return TaskPrioritySuggestion(
        summary: '太棒了！您目前没有未完成的任务。',
        items: [],
        isFromAI: true,
      );
    }

    // 准备任务数据
    final tasksData = uncompletedTasks.map((t) {
      return {
        'id': t.id,
        'title': t.title,
        'priority': _priorityToString(t.priority),
        'status': _statusToString(t.status),
        'dueTime': t.dueTime?.toIso8601String(),
        'isOverdue': t.isOverdue,
        'createdAt': t.createdAt.toIso8601String(),
      };
    }).toList();

    final prompt = '''
分析以下未完成的任务，给出处理优先级建议。请考虑：
1. 任务的紧急程度（是否逾期）
2. 截止时间
3. 任务优先级
4. 任务状态

任务列表：${_sanitizeForPrompt(jsonEncode(tasksData))}

请返回JSON格式：
{
  "summary": "总体建议概述（50字以内）",
  "items": [
    {
      "taskId": "任务ID",
      "title": "任务标题",
      "recommendedOrder": 1,
      "reason": "推荐理由（30字以内）",
      "suggestion": "具体建议（30字以内）",
      "priorityLevel": "高/中/低"
    }
  ]
}

要求：
- summary 要简洁明了
- 按推荐顺序排列
- 每个任务都要有明确的理由和建议
- 只返回JSON，不要其他内容
''';

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.receiveTimeout = const Duration(seconds: 15);

    final response = await dio.post(
      '${_config.baseUrl}/chat/completions',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config.apiKey}',
        },
      ),
      data: {
        'model': _config.model,
        'messages': [
          {'role': 'system', 'content': '你是一个专业的任务管理助手，擅长分析任务优先级并给出实用建议。'},
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.5,
      },
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final content = data['choices'][0]['message']['content'] as String;

      // 提取 JSON
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!);
        final items = (json['items'] as List)
            .map((item) => TaskSuggestionItem(
                  taskId: item['taskId'],
                  title: item['title'],
                  recommendedOrder: item['recommendedOrder'],
                  reason: item['reason'],
                  suggestion: item['suggestion'],
                  priorityLevel: item['priorityLevel'],
                ))
            .toList();

        return TaskPrioritySuggestion(
          summary: json['summary'] ?? '基于AI分析的建议',
          items: items,
          isFromAI: true,
        );
      }
    }

    // AI 解析失败，回退到本地规则
    return _generateLocalPrioritySuggestion(uncompletedTasks);
  }

  /// 本地规则生成优先级建议
  TaskPrioritySuggestion _generateLocalPrioritySuggestion(List<Task> tasks) {
    final uncompletedTasks = tasks.where((t) => !t.isCompleted).toList();

    if (uncompletedTasks.isEmpty) {
      return TaskPrioritySuggestion(
        summary: '太棒了！您目前没有未完成的任务。',
        items: [],
        isFromAI: false,
      );
    }

    final now = DateTime.now();
    final overdueTasks = uncompletedTasks.where((t) => t.isOverdue).toList();
    final highPriorityTasks = uncompletedTasks
        .where((t) => t.priority == TaskPriority.high && !t.isOverdue)
        .toList();
    final mediumPriorityTasks = uncompletedTasks
        .where((t) => t.priority == TaskPriority.medium && !t.isOverdue)
        .toList();
    final lowPriorityTasks = uncompletedTasks
        .where((t) => t.priority == TaskPriority.low && !t.isOverdue)
        .toList();

    // 按截止时间排序
    highPriorityTasks.sort((a, b) =>
        (a.dueTime ?? DateTime(2099)).compareTo(b.dueTime ?? DateTime(2099)));
    mediumPriorityTasks.sort((a, b) =>
        (a.dueTime ?? DateTime(2099)).compareTo(b.dueTime ?? DateTime(2099)));
    lowPriorityTasks.sort((a, b) =>
        (a.dueTime ?? DateTime(2099)).compareTo(b.dueTime ?? DateTime(2099)));

    // 组合排序后的任务
    final sortedTasks = [
      ...overdueTasks,
      ...highPriorityTasks,
      ...mediumPriorityTasks,
      ...lowPriorityTasks
    ];

    // 生成建议
    String summary;
    if (overdueTasks.isNotEmpty) {
      summary = '您有 ${overdueTasks.length} 个逾期任务，建议优先处理。';
    } else if (highPriorityTasks.isNotEmpty) {
      summary = '当前有 ${highPriorityTasks.length} 个高优先级任务需要关注。';
    } else {
      summary = '您有 ${uncompletedTasks.length} 个未完成任务，建议合理安排时间。';
    }

    // 生成建议项
    final items = <TaskSuggestionItem>[];
    for (var i = 0; i < sortedTasks.length; i++) {
      final task = sortedTasks[i];
      final order = i + 1;
      String reason;
      String suggestion;

      if (task.isOverdue) {
        final daysOverdue = now.difference(task.dueTime ?? now).inDays;
        reason = '已逾期 ${daysOverdue > 0 ? "$daysOverdue天" : ""}，需要紧急处理';
        suggestion = '立即开始处理';
      } else if (task.priority == TaskPriority.high) {
        reason = '高优先级任务';
        suggestion = '建议今天完成';
      } else if (task.dueTime != null) {
        final hoursUntilDue = task.dueTime!.difference(now).inHours;
        if (hoursUntilDue < 24) {
          reason = '截止时间在24小时内';
          suggestion = '尽快安排时间';
        } else if (hoursUntilDue < 72) {
          reason = '截止时间在3天内';
          suggestion = '本周完成';
        } else {
          reason = '有充裕时间';
          suggestion = '按计划进行';
        }
      } else {
        reason = '常规任务';
        suggestion = '合理安排时间';
      }

      items.add(TaskSuggestionItem(
        taskId: task.id,
        title: task.title,
        recommendedOrder: order,
        reason: reason,
        suggestion: suggestion,
        priorityLevel: _priorityToString(task.priority),
      ));
    }

    return TaskPrioritySuggestion(
      summary: summary,
      items: items,
      isFromAI: false,
    );
  }

  /// 生成智能建议
  Future<String> generateSuggestion(List<Task> tasks) async {
    if (!_config.enabled) {
      return _generateLocalSuggestion(tasks);
    }

    // TODO: 使用 AI 生成建议
    return _generateLocalSuggestion(tasks);
  }

  /// 转换优先级为字符串
  String _priorityToString(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return '高';
      case TaskPriority.low:
        return '低';
      default:
        return '中';
    }
  }

  /// 转换状态为字符串
  String _statusToString(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return '待处理';
      case TaskStatus.inProgress:
        return '进行中';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.cancelled:
        return '已取消';
      default:
        return '待处理';
    }
  }

  /// 检查AI模型是否可用（基于配置判断，不发送探测请求）
  bool isAIModelAvailable() {
    if (!_config.enabled) return false;
    if (_config.provider == 'local') return false;
    if (_config.apiKey.isEmpty ||
        _config.baseUrl.isEmpty ||
        _config.model.isEmpty) {
      return false;
    }
    return true;
  }

  /// 发送聊天消息
  Future<ChatResult> chatWithEngineInfo(String message,
      {List<Map<String, String>>? history, List<Task>? tasks}) async {
    // 先检查AI模型是否可用
    final aiAvailable = isAIModelAvailable();

    if (!aiAvailable) {
      // 使用本地规则引擎
      final response = _chatWithRules(message, tasks);
      return ChatResult(
        content: response,
        engineType: '本地规则引擎',
        isFromAI: false,
      );
    }

    try {
      // 构建包含任务信息的系统提示
      String systemPrompt = '你是一个智能任务助手，帮助用户管理任务、提供建议和解答问题。请用简洁友好的方式回复。';

      // 如果有任务列表，添加任务信息
      if (tasks != null && tasks.isNotEmpty) {
        final uncompletedTasks = tasks.where((t) => !t.isCompleted).toList();
        if (uncompletedTasks.isNotEmpty) {
          systemPrompt += '\n\n用户当前有 ${uncompletedTasks.length} 个未完成任务：\n';
          for (var i = 0; i < uncompletedTasks.length; i++) {
            final task = uncompletedTasks[i];
            final taskInfo = '${i + 1}. ${task.title}';
            final details = <String>[];
            if (task.priority != TaskPriority.medium) {
              details.add('优先级: ${_priorityToString(task.priority)}');
            }
            if (task.dueTime != null) {
              final now = DateTime.now();
              final hoursUntilDue = task.dueTime!.difference(now).inHours;
              if (task.isOverdue) {
                details.add('已逾期');
              } else if (hoursUntilDue < 24) {
                details.add('截止: 今天');
              } else if (hoursUntilDue < 48) {
                details.add('截止: 明天');
              } else {
                details.add('截止: ${task.dueTime!.toString().substring(0, 10)}');
              }
            }
            if (task.tagIds.isNotEmpty) {
              details.add('标签: ${task.tagIds.join(', ')}');
            }

            systemPrompt += details.isEmpty
                ? '$taskInfo\n'
                : '$taskInfo (${details.join(', ')})\n';
          }
          systemPrompt += '\n请根据这些任务信息，结合用户的问题，提供更有针对性的建议。';
        } else {
          systemPrompt += '\n\n用户目前没有未完成的任务。';
        }
      }

      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];

      if (history != null && history.isNotEmpty) {
        messages.addAll(history);
      }

      messages.add({'role': 'user', 'content': message});

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 120);

      final response = await dio.post(
        '${_config.baseUrl}/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_config.apiKey}',
          },
        ),
        data: {
          'model': _config.model,
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 1000,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // 智谱等 provider 可能返回 content null/空（如触发审核或深度思考模式），做防御
        final message = data['choices']?[0]?['message'] as Map<String, dynamic>?;
        var content = (message?['content'] as String?) ?? '';
        // content 为空时尝试 reasoning_content（部分 provider 把内容放这里）
        if (content.isEmpty) {
          content = (message?['reasoning_content'] as String?) ?? '';
        }
        final engineName = currentModelDisplayName;

        return ChatResult(
          content: content.isEmpty ? '（AI 返回了空内容，可能触发了内容审核，请换个问法试试）' : content,
          engineType: engineName,
          isFromAI: true,
        );
      }
    } catch (e) {
      // 提取更详细的错误信息用于诊断
      String errorDetail = '';
      if (e is DioException) {
        if (e.response != null) {
          errorDetail = 'HTTP ${e.response?.statusCode}: ${e.response?.data}';
        } else {
          errorDetail = e.type.toString();
        }
      } else {
        errorDetail = e.toString();
      }
      debugPrint('AI 聊天失败: $errorDetail');
      debugPrint('AI 配置: baseUrl=${_config.baseUrl}, model=${_config.model}, apiKey=${_config.apiKey.length > 8 ? '${_config.apiKey.substring(0, 4)}...${_config.apiKey.substring(_config.apiKey.length - 4)}' : "(empty)"}');
      final localResponse = _chatWithRules(message, tasks);
      final engineLabel = _config.enabled
          ? '$currentModelDisplayName（连接失败，已降级）'
          : '本地规则引擎';
      return ChatResult(
        content: '$localResponse\n\n---\n⚠️ AI服务连接失败: $errorDetail',
        engineType: engineLabel,
        isFromAI: false,
      );
    }

    // 其他情况，使用本地规则引擎
    final response = _chatWithRules(message, tasks);
    return ChatResult(
      content: response,
      engineType: '本地规则引擎',
      isFromAI: false,
    );
  }

  /// 发送聊天消息（保持向后兼容）
  Future<String> chat(String message,
      {List<Map<String, String>>? history}) async {
    final result = await chatWithEngineInfo(message, history: history);
    return result.content;
  }

  /// 本地规则聊天
  String _chatWithRules(String message, [List<Task>? tasks]) {
    final lowerMsg = message.toLowerCase();

    if (lowerMsg.contains('你好') ||
        lowerMsg.contains('hi') ||
        lowerMsg.contains('hello')) {
      return '你好！我是智能任务助手，有什么可以帮助你的吗？';
    }

    if (lowerMsg.contains('帮助') || lowerMsg.contains('help')) {
      return '我可以帮助你：\n• 创建和管理任务\n• 设置提醒\n• 智能分析任务优先级\n• 提供工作效率建议\n\n试试说："明天下午3点开会"';
    }

    if (lowerMsg.contains('建议') || lowerMsg.contains('推荐')) {
      if (tasks != null && tasks.isNotEmpty) {
        final uncompletedTasks = tasks.where((t) => !t.isCompleted).toList();
        if (uncompletedTasks.isNotEmpty) {
          return '建议你先完成高优先级的任务，合理安排时间，避免拖延。你当前有 ${uncompletedTasks.length} 个未完成任务需要处理。';
        }
      }
      return '建议你先完成高优先级的任务，合理安排时间，避免拖延。如果任务较多，可以按"四象限法则"分类处理。';
    }

    if (lowerMsg.contains('统计') || lowerMsg.contains('概览')) {
      return '你可以在"统计"页面查看任务完成情况和数据概览。';
    }

    return '我理解你的问题。目前使用本地规则引擎，功能有限。请在设置中配置AI服务以获得更智能的体验。';
  }

  /// 测试AI连接
  Future<Map<String, dynamic>> testConnection() async {
    if (!_config.enabled) {
      return {
        'success': false,
        'message': 'AI服务未启用',
      };
    }

    if (_config.provider == 'local') {
      return {
        'success': true,
        'message': '使用本地规则引擎，无需连接测试',
      };
    }

    if (_config.apiKey.isEmpty) {
      return {
        'success': false,
        'message': '请填写API Key',
      };
    }

    if (_config.baseUrl.isEmpty) {
      return {
        'success': false,
        'message': '请填写API地址',
      };
    }

    if (_config.model.isEmpty) {
      return {
        'success': false,
        'message': '请填写模型名称',
      };
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final response = await dio.post(
        '${_config.baseUrl}/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_config.apiKey}',
          },
        ),
        data: {
          'model': _config.model,
          'messages': [
            {'role': 'user', 'content': 'Hi'}
          ],
          'max_tokens': 10,
        },
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': '连接成功！模型 ${_config.model} 响应正常',
        };
      } else {
        return {
          'success': false,
          'message': '连接失败: HTTP ${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      String errorMsg = '连接失败';
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMsg = '连接超时，请检查网络或API地址';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = '无法连接到服务器，请检查API地址是否正确';
      } else if (e.response?.statusCode == 401) {
        errorMsg = 'API Key 无效';
      } else if (e.response?.statusCode == 404) {
        errorMsg = 'API地址不存在或模型名称错误';
      } else if (e.response?.data != null) {
        final errorData = e.response?.data;
        if (errorData is Map && errorData['error'] != null) {
          errorMsg = errorData['error']['message'] ?? errorMsg;
        }
      }
      return {
        'success': false,
        'message': errorMsg,
      };
    } catch (e) {
      return {
        'success': false,
        'message': '连接失败: $e',
      };
    }
  }

  /// 获取当前配置的模型显示名称
  String get currentModelDisplayName {
    if (!_config.enabled) {
      return '本地规则引擎';
    }

    final providerNames = {
      'local': '本地规则引擎',
      'ollama': 'Ollama',
      'openai': 'OpenAI',
      'deepseek': 'DeepSeek',
      'qwen': '通义千问',
      'zhipu': '智谱AI',
      'kimi': 'Kimi',
      'custom': '自定义API',
    };

    final providerName = providerNames[_config.provider] ?? _config.provider;

    if (_config.model.isNotEmpty) {
      return '$providerName (${_config.model})';
    }
    return providerName;
  }

  /// 本地建议生成
  String _generateLocalSuggestion(List<Task> tasks) {
    final now = DateTime.now();
    final overdueTasks = tasks.where((t) => t.isOverdue).toList();
    final highPriorityTasks = tasks
        .where((t) => !t.isCompleted && t.priority == TaskPriority.high)
        .toList();
    final todayTasks = tasks.where((t) {
      if (t.dueTime == null) return false;
      return t.dueTime!.year == now.year &&
          t.dueTime!.month == now.month &&
          t.dueTime!.day == now.day;
    }).toList();

    if (overdueTasks.isNotEmpty) {
      return '您有 ${overdueTasks.length} 个逾期任务，建议优先处理「${overdueTasks.first.title}」。';
    }

    if (highPriorityTasks.isNotEmpty) {
      return '建议优先处理「${highPriorityTasks.first.title}」，优先级较高需要尽快完成。';
    }

    if (todayTasks.isNotEmpty) {
      final hour = now.hour;
      if (hour < 12) {
        return '上午精神状态较好，适合处理「${todayTasks.first.title}」等需要专注的任务。';
      } else if (hour < 18) {
        return '下午时间适合处理日常任务，当前有 ${todayTasks.length} 个今日任务待完成。';
      } else {
        return '今日还有 ${todayTasks.where((t) => !t.isCompleted).length} 个任务未完成，建议合理安排时间。';
      }
    }

    return '暂无紧急任务，可以规划新的工作安排。';
  }

  /// 测试本地LLM连接
  Future<bool> testLocalLLMConnection(String address, String model) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final response = await dio.post(
        '$address/api/generate',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'prompt': 'Hi',
          'stream': false,
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('本地LLM连接测试失败: $e');
      return false;
    }
  }

  /// 测试远程API连接
  Future<bool> testAPIConnection(
      String apiKey, String apiBase, String apiModel) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final response = await dio.post(
        '$apiBase/chat/completions',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
        ),
        data: {
          'model': apiModel,
          'messages': [
            {'role': 'user', 'content': 'Hi'}
          ],
          'max_tokens': 10,
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('API连接测试失败: $e');
      return false;
    }
  }

  /// Sanitize user input before embedding into AI prompts to strip common
  /// prompt-injection patterns.
  String _sanitizeForPrompt(String input) {
    // Dart 的 RegExp 不支持内联 (?i) 标志，必须用 caseSensitive: false
    return input
        .replaceAll(
            RegExp(r'ignore\s+(the\s+)?(above|previous|instructions)',
                caseSensitive: false),
            '[filtered]')
        .replaceAll(
            RegExp(r'you\s+are\s+now', caseSensitive: false), '[filtered]')
        .replaceAll(RegExp(r'system\s*:', caseSensitive: false), '')
        .replaceAll(RegExp(r'assistant\s*:', caseSensitive: false), '');
  }
}
