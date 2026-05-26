import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/task.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  String generateCSV(List<Task> tasks) {
    final buffer = StringBuffer();
    buffer.writeln('﻿ID,标题,内容,状态,优先级,负责人,截止时间,完成时间,创建时间');
    for (final t in tasks) {
      buffer.writeln([
        t.id,
        _escape(t.title),
        _escape(t.content ?? ''),
        t.status.name,
        t.priority.name,
        _escape(t.assignee ?? ''),
        t.dueTime?.toIso8601String() ?? '',
        t.completedAt?.toIso8601String() ?? '',
        t.createdAt.toIso8601String(),
      ].join(','));
    }
    return buffer.toString();
  }

  String generateJSON(List<Task> tasks) {
    final items = tasks.map((t) => {
      'id': t.id,
      'title': t.title,
      'content': t.content,
      'status': t.status.name,
      'priority': t.priority.name,
      'assignee': t.assignee,
      'dueTime': t.dueTime?.toIso8601String(),
      'completedAt': t.completedAt?.toIso8601String(),
      'createdAt': t.createdAt.toIso8601String(),
    }).toList();
    return const JsonEncoder.withIndent('  ').convert(items);
  }

  Future<void> exportAndShare(List<Task> tasks, {bool asJson = false}) async {
    final dir = await getTemporaryDirectory();
    final ext = asJson ? 'json' : 'csv';
    final content = asJson ? generateJSON(tasks) : generateCSV(tasks);
    final file = File('${dir.path}/tasks_export.$ext');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], text: '任务导出');
  }

  String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""').replaceAll('\r\n', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ')}"';
    }
    return value;
  }
}
