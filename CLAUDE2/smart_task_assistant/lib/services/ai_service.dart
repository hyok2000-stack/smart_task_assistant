import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';

/// AI 服务配置
class AIConfig {
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

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'enabled': enabled,
      };

  factory AIConfig.fromJson(Map<String, dynamic> json) {
    return AIConfig(
      provider: json['provider'] ?? 'local',
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

  ParsedTask({
    required this.title,
    this.content,
    this.dueTime,
    this.priority = TaskPriority.medium,
    this.assignee,
    this.tags = const [],
  });
}

/// AI 服务（单例模式）
class AIService {
  static const String _configKey = 'ai_config';
  static final AIService _instance = AIService._internal();
  
  factory AIService() => _instance;
  
  AIService._internal();
  
  AIConfig _config = AIConfig();
  bool _configLoaded = false;

  AIConfig get config => _config;

  /// 加载配置
  Future<void> loadConfig() async {
    if (_configLoaded) {
      debugPrint('AI配置已加载: enabled=${_config.enabled}, provider=${_config.provider}');
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);
      if (configJson != null) {
        _config = AIConfig.fromJson(jsonDecode(configJson));
        debugPrint('AI配置加载成功: enabled=${_config.enabled}, provider=${_config.provider}, baseUrl=${_config.baseUrl}');
      }
      _configLoaded = true;
    } catch (e) {
      debugPrint('加载 AI 配置失败: $e');
    }
  }

  /// 保存配置
  Future<void> saveConfig() async {
    try {
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
    debugPrint('AI配置已更新: enabled=${_config.enabled}, provider=${_config.provider}, baseUrl=${_config.baseUrl}');
  }

  /// 使用本地规则解析（公开方法，用于默认解析）
  ParsedTask parseTaskLocal(String input) {
    return _parseWithRules(input);
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
    final timeKeywords = ['今天', '今日', '明天', '后天', '大后天', '下周', '本周',
        '周一', '周二', '周三', '周四', '周五', '周六', '周日', '周天',
        '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日', '星期天',
        '上午', '下午', '晚上', '中午', '早上', '早晨', '晚间'];

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
    final assigneeMatch = assigneeRegex1.firstMatch(input) ?? assigneeRegex2.firstMatch(input);
    if (assigneeMatch != null) {
      assignee = assigneeMatch.group(1);
      title = title.replaceAll(assigneeRegex1, '').replaceAll(assigneeRegex2, '').trim();
    }

    // 识别优先级关键词
    if (title.contains('紧急') || title.contains('重要') || title.contains('急') || title.contains('尽快')) {
      priority = TaskPriority.high;
      title = title.replaceAll(RegExp(r'(紧急|重要|急|尽快)'), '').trim();
    } else if (title.contains('不急') || title.contains('有空') || title.contains('闲暇')) {
      priority = TaskPriority.low;
      title = title.replaceAll(RegExp(r'(不急|有空|闲暇)'), '').trim();
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
          '一': 1, '二': 2, '三': 3, '四': 4,
          '五': 5, '六': 6, '七': 7, '日': 7, '天': 7,
        };
        final targetWeekday = weekdayMap[weekdayMatch.group(1)] ?? 1;
        final daysUntilNextWeek = 7 - now.weekday + targetWeekday;
        dueTime = DateTime(now.year, now.month, now.day + daysUntilNextWeek, 18, 0);
        title = title.replaceAll(weekdayMatch.group(0)!, '').trim();
      }
      title = title.replaceAll('下周', '').trim();
    }
    // 本周几
    else if (title.contains('本周')) {
      final weekdayMatch = RegExp(r'本周([一二三四五六七日天])').firstMatch(title);
      if (weekdayMatch != null) {
        final weekdayMap = {
          '一': 1, '二': 2, '三': 3, '四': 4,
          '五': 5, '六': 6, '七': 7, '日': 7, '天': 7,
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
          '一': 1, '二': 2, '三': 3, '四': 4,
          '五': 5, '六': 6, '七': 7, '日': 7, '天': 7,
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
      if (month < now.month) year++; // 如果月份已过，则为明年
      dueTime = DateTime(year, month, day, dueTime?.hour ?? 18, dueTime?.minute ?? 0);
      title = title.replaceAll(dateRegex, '').trim();
    }

    // 识别具体时间 HH:mm 或 X点X分
    final timeRegex = RegExp(r'(\d{1,2})[:点时](\d{0,2})?分?');
    final timeMatch = timeRegex.firstMatch(title);
    if (timeMatch != null) {
      final hour = int.tryParse(timeMatch.group(1)!) ?? 18;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        if (dueTime != null) {
          dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, hour, minute);
        } else {
          // 没有日期，默认今天
          dueTime = DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
      title = title.replaceAll(timeRegex, '').trim();
    }

    // 识别时段：上午/下午/晚上
    if (dueTime != null) {
      if (title.contains('上午') || title.contains('早上') || title.contains('早晨')) {
        dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 9, 0);
        title = title.replaceAll(RegExp(r'(上午|早上|早晨)'), '').trim();
      } else if (title.contains('中午')) {
        dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 12, 0);
        title = title.replaceAll('中午', '').trim();
      } else if (title.contains('下午')) {
        if (dueTime.hour == 18) dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 15, 0);
        title = title.replaceAll('下午', '').trim();
      } else if (title.contains('晚上') || title.contains('晚间')) {
        dueTime = DateTime(dueTime.year, dueTime.month, dueTime.day, 20, 0);
        title = title.replaceAll(RegExp(r'(晚上|晚间)'), '').trim();
      }
    }

    // 识别X天后
    final daysAfterRegex = RegExp(r'(\d+)天后');
    final daysAfterMatch = daysAfterRegex.firstMatch(title);
    if (daysAfterMatch != null) {
      final days = int.tryParse(daysAfterMatch.group(1)!) ?? 1;
      dueTime = DateTime(now.year, now.month, now.day + days, 18, 0);
      title = title.replaceAll(daysAfterRegex, '').trim();
    }

    // 识别X小时后
    final hoursAfterRegex = RegExp(r'(\d+)小时后');
    final hoursAfterMatch = hoursAfterRegex.firstMatch(title);
    if (hoursAfterMatch != null) {
      final hours = int.tryParse(hoursAfterMatch.group(1)!) ?? 1;
      dueTime = now.add(Duration(hours: hours));
      title = title.replaceAll(hoursAfterRegex, '').trim();
    }

    // 清理多余空格和标点
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    title = title.replaceAll(RegExp(r'[，。！？、]'), '').trim();

    return ParsedTask(
      title: title.isNotEmpty ? title : input,
      dueTime: dueTime,
      priority: priority,
      assignee: assignee,
      tags: tags,
    );
  }

  /// 使用 AI 服务解析
  Future<ParsedTask?> _parseWithAI(String input) async {
    if (_config.apiKey.isEmpty || _config.baseUrl.isEmpty) {
      return _parseWithRules(input);
    }

    final prompt = '''
请从以下文本中提取任务信息，返回 JSON 格式：
{
  "title": "任务标题",
  "content": "任务详情（可选）",
  "dueTime": "YYYY-MM-DD HH:mm（可选）",
  "priority": "high/medium/low",
  "assignee": "负责人（可选）",
  "tags": ["标签1", "标签2"]
}

文本：$input

只返回 JSON，不要其他内容。
''';

    try {
      final dio = Dio();
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
          return ParsedTask(
            title: json['title'] ?? input,
            content: json['content'],
            dueTime: json['dueTime'] != null 
                ? DateTime.tryParse(json['dueTime']) 
                : null,
            priority: _parsePriority(json['priority']),
            assignee: json['assignee'],
            tags: List<String>.from(json['tags'] ?? []),
          );
        }
      }
    } catch (e) {
      debugPrint('AI API 调用失败: $e');
    }

    return _parseWithRules(input);
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

  /// 生成智能建议
  Future<String> generateSuggestion(List<Task> tasks) async {
    if (!_config.enabled) {
      return _generateLocalSuggestion(tasks);
    }

    // TODO: 使用 AI 生成建议
    return _generateLocalSuggestion(tasks);
  }

  /// 发送聊天消息
  Future<String> chat(String message, {List<Map<String, String>>? history}) async {
    if (!_config.enabled || _config.apiKey.isEmpty || _config.baseUrl.isEmpty) {
      return _chatWithRules(message);
    }

    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': '你是一个智能任务助手，帮助用户管理任务、提供建议和解答问题。请用简洁友好的方式回复。'},
      ];
      
      if (history != null && history.isNotEmpty) {
        messages.addAll(history);
      }
      
      messages.add({'role': 'user', 'content': message});

      final dio = Dio();
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
        return data['choices'][0]['message']['content'] as String;
      }
    } catch (e) {
      debugPrint('AI 聊天失败: $e');
    }

    return _chatWithRules(message);
  }

  /// 本地规则聊天
  String _chatWithRules(String message) {
    final lowerMsg = message.toLowerCase();
    
    if (lowerMsg.contains('你好') || lowerMsg.contains('hi') || lowerMsg.contains('hello')) {
      return '你好！我是智能任务助手，有什么可以帮助你的吗？';
    }
    
    if (lowerMsg.contains('帮助') || lowerMsg.contains('help')) {
      return '我可以帮助你：\n• 创建和管理任务\n• 设置提醒\n• 智能分析任务优先级\n• 提供工作效率建议\n\n试试说："明天下午3点开会"';
    }
    
    if (lowerMsg.contains('建议') || lowerMsg.contains('推荐')) {
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
    final highPriorityTasks = tasks.where((t) => 
        !t.isCompleted && t.priority == TaskPriority.high).toList();
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
}