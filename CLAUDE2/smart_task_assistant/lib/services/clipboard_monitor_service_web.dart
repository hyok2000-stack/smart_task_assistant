/// Web 平台剪贴板监视实现
library;
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

// 已注册的 paste 监听（用于注销；package:web 的 addEventListener 不返回句柄）
JSFunction? _pasteHandler;

// 全局回调
Function(String)? _onClipboardChanged;

/// 开始监视剪贴板（Web平台）
void startMonitoringWeb() {
  if (_pasteHandler != null) return; // 已在监听
  // toJS 转换要求同步函数：异步处理放到 _handlePaste 里 fire-and-forget
  _pasteHandler = ((web.Event _) {
    _handlePaste();
  }).toJS;
  web.document.addEventListener('paste', _pasteHandler!);
  debugPrint('剪贴板监视已启动 (Web)');
}

/// 读取剪贴板并分发给全局回调
Future<void> _handlePaste() async {
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
}

/// 停止监视剪贴板（Web平台）
void stopMonitoringWeb() {
  if (_pasteHandler != null) {
    web.document.removeEventListener('paste', _pasteHandler!);
    _pasteHandler = null;
  }
  debugPrint('剪贴板监视已停止 (Web)');
}

/// 保存设置到本地存储（Web平台）
void saveSettingsWeb(bool enabled) {
  web.window.localStorage
      .setItem('clipboard_monitor_enabled', enabled.toString());
}

/// 从本地存储加载设置（Web平台）
String? loadSettingsWeb() {
  return web.window.localStorage.getItem('clipboard_monitor_enabled');
}

/// 获取剪贴板文本
Future<String?> _getClipboardText() async {
  try {
    final clipboard = web.window.navigator.clipboard;
    // JSPromise<JSString> → Future<JSString> → String
    final text = await clipboard.readText().toDart;
    return text.toDart;
  } catch (e) {
    debugPrint('读取剪贴板失败: $e');
    return null;
  }
}

/// 设置剪贴板变化回调
void setClipboardCallback(Function(String)? callback) {
  _onClipboardChanged = callback;
}
