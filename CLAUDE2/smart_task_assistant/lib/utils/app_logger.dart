import 'dart:async';
import 'package:flutter/foundation.dart';

/// 应用日志记录器
/// 用于在应用内记录和查看日志
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  // 日志条目
  final List<LogEntry> _logs = [];
  final StreamController<List<LogEntry>> _logController =
      StreamController.broadcast();

  // 最大日志条数
  static const int _maxLogs = 500;

  /// 获取日志流
  Stream<List<LogEntry>> get logStream => _logController.stream;

  /// 获取所有日志
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// 清空日志
  void clear() {
    _logs.clear();
    _notifyListeners();
  }

  /// 记录日志
  void log(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );

    _logs.add(entry);

    // 限制日志数量
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }

    _notifyListeners();

    // 同时输出到控制台
    if (kDebugMode) {
      final prefix = _getLevelPrefix(level);
      debugPrint('$prefix $message');
    }
  }

  void debug(String message) => log(message, level: LogLevel.debug);
  void info(String message) => log(message, level: LogLevel.info);
  void warning(String message) => log(message, level: LogLevel.warning);
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    final fullMessage = error != null ? '$message: $error' : message;
    log(fullMessage, level: LogLevel.error);

    if (stackTrace != null && kDebugMode) {
      debugPrint('Stack trace:\n$stackTrace');
    }
  }

  String _getLevelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '[DEBUG]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.warning:
        return '[WARNING]';
      case LogLevel.error:
        return '[ERROR]';
    }
  }

  void _notifyListeners() {
    _logController.add(List.from(_logs));
  }

  /// 销毁
  void dispose() {
    _logController.close();
  }
}

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 日志条目
class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
  });

  /// 获取格式化的时间字符串
  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  /// 获取级别图标
  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  /// 获取级别颜色
  String get levelColor {
    switch (level) {
      case LogLevel.debug:
        return '#6B7280';
      case LogLevel.info:
        return '#3B82F6';
      case LogLevel.warning:
        return '#F59E0B';
      case LogLevel.error:
        return '#EF4444';
    }
  }
}

/// 全局日志实例
final appLogger = AppLogger();
