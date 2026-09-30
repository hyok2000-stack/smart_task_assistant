/// Web 平台剪贴板监视实现
library;
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';

// 全局订阅
StreamSubscription? _pasteSubscription;

// 全局回调
Function(String)? _onClipboardChanged;

/// 开始监视剪贴板（Web平台）
void startMonitoringWeb() {
  _pasteSubscription = html.document.onPaste.listen((event) async {
    try {
      // 获取剪贴板数据
      final clipboardData = await _getClipboardText();
      if (clipboardData != null && clipboardData.isNotEmpty) {
        // 通过全局回调处理
        _onClipboardChanged?.call(clipboardData);
      }
    } catch (e) {
      debugPrint('剪贴板监视错误: $e');
    }
  });
  debugPrint('剪贴板监视已启动 (Web)');
}

/// 停止监视剪贴板（Web平台）
void stopMonitoringWeb() {
  _pasteSubscription?.cancel();
  _pasteSubscription = null;
  debugPrint('剪贴板监视已停止 (Web)');
}

/// 保存设置到本地存储（Web平台）
void saveSettingsWeb(bool enabled) {
  html.window.localStorage['clipboard_monitor_enabled'] = enabled.toString();
}

/// 从本地存储加载设置（Web平台）
String? loadSettingsWeb() {
  return html.window.localStorage['clipboard_monitor_enabled'];
}

/// 获取剪贴板文本
Future<String?> _getClipboardText() async {
  try {
    final items = await html.window.navigator.clipboard?.readText();
    return items;
  } catch (e) {
    debugPrint('读取剪贴板失败: $e');
    return null;
  }
}

/// 设置剪贴板变化回调
void setClipboardCallback(Function(String)? callback) {
  _onClipboardChanged = callback;
}