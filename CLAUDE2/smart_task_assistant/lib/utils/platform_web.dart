/// 平台特定的 Web 工具库
/// 这个文件只在 Web 平台使用

import 'dart:html' as html;

/// 获取 Web 存储的值
String? getWebStorage(String key) {
  try {
    return html.window.localStorage[key];
  } catch (e) {
    return null;
  }
}

/// 设置 Web 存储的值
void setWebStorage(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (e) {
    // 忽略错误
  }
}
