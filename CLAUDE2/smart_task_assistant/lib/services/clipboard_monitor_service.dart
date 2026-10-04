import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

// 条件导入
import 'clipboard_monitor_service_web.dart'
    if (dart.library.io) 'clipboard_monitor_service_stub.dart';
import 'clipboard_monitor_service_native.dart';

/// 剪贴板监视服务
/// 在 Web 平台上监听粘贴事件，在 Android 平台上使用前台服务监听剪贴板变化
class ClipboardMonitorService {
  static final ClipboardMonitorService _instance =
      ClipboardMonitorService._internal();
  factory ClipboardMonitorService() => _instance;
  ClipboardMonitorService._internal();

  bool _isEnabled = false;
  bool _isMonitoring = false;
  bool _isInitialized = false; // 初始化状态标志

  // 上一次的剪贴板内容，避免重复弹出

  // 导航键，用于弹出窗口

  // 回调函数，用于显示任务创建窗口

  // Android 原生服务实例
  ClipboardMonitorServiceNative? _nativeService;

  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;

  /// 初始化服务
  void init(GlobalKey<NavigatorState> navigatorKey,
      Function(String content) onClipboardContent) {
    // 如果已经初始化，先清理现有的资源
    if (_isMonitoring) {
      dispose();
    }

    _isInitialized = true;

    // 根据平台选择不同的实现
    if (kIsWeb) {
      setClipboardCallback(onClipboardContent);
    } else if (Platform.isAndroid) {
      _nativeService = ClipboardMonitorServiceNative();
      _nativeService?.setCallback(onClipboardContent);
    }

    debugPrint('剪贴板监视服务已初始化');
  }

  /// 启用/禁用剪贴板监视
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;

    if (kIsWeb) {
      if (enabled && !_isMonitoring) {
        startMonitoringWeb();
        _isMonitoring = true;
      } else if (!enabled && _isMonitoring) {
        stopMonitoringWeb();
        _isMonitoring = false;
      }
      saveSettingsWeb(enabled);
    } else if (Platform.isAndroid) {
      if (enabled && !_isMonitoring) {
        final success = await _nativeService?.startService() ?? false;
        if (success) {
          _isMonitoring = true;
        }
      } else if (!enabled && _isMonitoring) {
        final success = await _nativeService?.stopService() ?? false;
        if (success) {
          _isMonitoring = false;
        }
      }
    } else {
      // 其他平台暂不支持剪贴板监视
      debugPrint('当前平台不支持剪贴板自动监视');
    }
  }

  /// 从本地存储加载设置
  Future<bool> loadSettings() async {
    if (kIsWeb) {
      final saved = loadSettingsWeb();
      if (saved == 'true') {
        _isEnabled = true;
        startMonitoringWeb();
        _isMonitoring = true;
      }
    } else if (Platform.isAndroid) {
      // Android 平台从 SharedPreferences 加载设置
      // 这里可以添加存储逻辑
    }
    return _isEnabled;
  }

  /// 清除缓存的内容（用于允许再次弹出相同内容）
  void clearCache() {
  }

  /// 释放资源
  void dispose() {
    if (kIsWeb && _isMonitoring) {
      stopMonitoringWeb();
    } else if (Platform.isAndroid) {
      _nativeService?.dispose();
    }
    _isMonitoring = false;
  }
}

/// 全局剪贴板监视服务实例
final clipboardMonitorService = ClipboardMonitorService();
