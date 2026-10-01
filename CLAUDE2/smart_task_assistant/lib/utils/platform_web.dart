/// 平台特定的 Web 工具库
/// 这个文件只在 Web 平台使用
library;

import 'package:web/web.dart' as web;

/// 获取 Web 存储的值
String? getWebStorage(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (e) {
    return null;
  }
}

/// 设置 Web 存储的值
void setWebStorage(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (e) {
    // 忽略错误
  }
}
