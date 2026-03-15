import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../utils/app_logger.dart';

/// 日志查看器对话框
class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.description_outlined, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          Text(l.isZh ? '应用日志' : 'Application Logs'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
            tooltip: l.isZh ? '刷新' : 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              appLogger.clear();
              setState(() {});
            },
            tooltip: l.isZh ? '清空日志' : 'Clear Logs',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: StreamBuilder<List<LogEntry>>(
          stream: appLogger.logStream,
          initialData: appLogger.logs,
          builder: (context, snapshot) {
            final logs = snapshot.data ?? [];

            if (logs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 64,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.isZh ? '暂无日志' : 'No logs yet',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              reverse: true, // 最新的日志在上面
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: index % 2 == 0
                        ? Colors.grey.shade50
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.shade200,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 时间
                      Text(
                        log.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 图标
                      Text(
                        log.levelIcon,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      // 消息
                      Expanded(
                        child: Text(
                          log.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: _parseColor(log.levelColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }

  Color _parseColor(String hexColor) {
    try {
      hexColor = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }
}
