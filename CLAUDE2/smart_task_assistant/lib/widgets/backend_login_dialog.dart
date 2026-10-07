import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backend_api_service.dart';
import '../providers/task_provider.dart';

/// 后台同步登录对话框（自包含：输入框自带控制器，登录成功返回 true）。
/// 供首页"未登录"云图标与设置页"登录后台同步"入口复用；
/// 注册/退出登录等账号管理动作仍保留在设置页的完整版里。
Future<bool> showBackendLoginDialog(BuildContext context) async {
  final backend = BackendApiService.instance;
  final baseUrlController = TextEditingController(text: backend.baseUrl);
  final accountController =
      TextEditingController(text: backend.account ?? '');
  final passwordController =
      TextEditingController(text: backend.password ?? '');
  var isLoading = false;

  final loggedIn = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('后台同步登录'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 420
                ? 420
                : MediaQuery.of(context).size.width * 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baseUrlController,
                  decoration: const InputDecoration(
                    labelText: '后台地址',
                    hintText: 'http://localhost:4100/api',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: accountController,
                  decoration: const InputDecoration(labelText: '账号'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context, false),
              child: const Text('关闭'),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setDialogState(() => isLoading = true);
                      final taskProvider = context.read<TaskProvider>();
                      try {
                        final session = await backend.login(
                          account: accountController.text.trim(),
                          password: passwordController.text,
                          baseUrl: baseUrlController.text.trim(),
                          rememberPassword: true,
                        );
                        await backend.bindDevice(
                          deviceName:
                              kIsWeb ? 'Web APP' : Platform.localHostname,
                          platform: kIsWeb ? 'web' : Platform.operatingSystem,
                        );
                        final syncedCount =
                            await taskProvider.syncAllWithBackend();
                        if (!context.mounted) return;
                        Navigator.pop(context, true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已登录：${session.nickname}，同步 $syncedCount 个云端变更',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('登录失败：$e')),
                        );
                      } finally {
                        setDialogState(() => isLoading = false);
                      }
                    },
              child: Text(isLoading ? '登录中...' : '登录'),
            ),
          ],
        );
      },
    ),
  );
  return loggedIn ?? false;
}
