/// 非Web平台剪贴板监视存根
/// 此文件在非Web平台编译时使用
library;
import 'package:flutter/material.dart';

/// 开始监视剪贴板（非Web平台空实现）
void startMonitoringWeb() {
  debugPrint('非Web平台不支持剪贴板自动监视');
}

/// 停止监视剪贴板（非Web平台空实现）
void stopMonitoringWeb() {
  // 非Web平台不执行任何操作
}

/// 保存设置到本地存储（非Web平台空实现）
void saveSettingsWeb(bool enabled) {
  // 非Web平台使用其他存储方式
}

/// 从本地存储加载设置（非Web平台空实现）
String? loadSettingsWeb() {
  return null;
}

/// 设置剪贴板变化回调
void setClipboardCallback(Function(String)? callback) {
  // 非Web平台不支持
}