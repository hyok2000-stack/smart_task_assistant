import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 解析 #RRGGBB / #AARRGGBB / RRGGBB 颜色字符串。
///
/// add_task_screen 与 quick_add_modal 的标签颜色共用此实现；
/// 长度不合法（非 6/8 位十六进制）或解析失败均返回 [fallback]，不抛异常。
Color parseHexColor(String hex, {Color fallback = AppTheme.primaryColor}) {
  try {
    var value = hex.replaceAll('#', '').trim();
    if (value.length != 6 && value.length != 8) return fallback;
    if (value.length == 6) value = 'FF$value';
    return Color(int.parse(value, radix: 16));
  } catch (_) {
    return fallback;
  }
}
