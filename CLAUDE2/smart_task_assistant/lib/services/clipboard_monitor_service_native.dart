import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android 平台剪贴板监控服务
/// 使用前台服务监听剪贴板变化
class ClipboardMonitorServiceNative {
  static const MethodChannel _channel = MethodChannel(
    'com.smarttask.smart_task_assistant/clipboard_service',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.smarttask.smart_task_assistant/clipboard_monitor',
  );

  static final ClipboardMonitorServiceNative _instance =
      ClipboardMonitorServiceNative._internal();
  factory ClipboardMonitorServiceNative() => _instance;
  ClipboardMonitorServiceNative._internal();

  bool _isEnabled = false;
  StreamSubscription<String>? _subscription;

  // 回调函数
  Function(String content)? _onClipboardContent;

  bool get isEnabled => _isEnabled;

  /// 启动剪贴板监控服务
  Future<bool> startService() async {
    try {
      final bool result = await _channel.invokeMethod('startService');
      if (result) {
        _startListening();
        _isEnabled = true;
      }
      return result;
    } catch (e) {
      debugPrint('启动剪贴板服务失败: $e');
      return false;
    }
  }

  /// 停止剪贴板监控服务
  Future<bool> stopService() async {
    try {
      final bool result = await _channel.invokeMethod('stopService');
      if (result) {
        _stopListening();
        _isEnabled = false;
      }
      return result;
    } catch (e) {
      debugPrint('停止剪贴板服务失败: $e');
      return false;
    }
  }

  /// 开始监听剪贴板变化
  void _startListening() {
    _subscription?.cancel();
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as String)
        .listen(
      (content) {
        if (_onClipboardContent != null && content.trim().isNotEmpty) {
          _onClipboardContent!(content);
        }
      },
      onError: (error) {
        debugPrint('剪贴板监听错误: $error');
      },
    );
  }

  /// 停止监听剪贴板变化
  void _stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// 设置剪贴板变化回调
  void setCallback(Function(String content) callback) {
    _onClipboardContent = callback;
  }

  /// 释放资源
  void dispose() {
    _stopListening();
    if (_isEnabled) {
      stopService();
    }
  }
}
