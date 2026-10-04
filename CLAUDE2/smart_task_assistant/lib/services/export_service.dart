import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';
import '../database/database_helper.dart';

// 字段名→CSV 表头中文名 的映射（generateCSV 使用中文表头）
const _csvHeaderMap = {
  'ID': 'id',
  '标题': 'title',
  '内容': 'content',
  '状态': 'status',
  '优先级': 'priority',
  '负责人': 'assignee',
  '截止时间': 'dueTime',
  '完成时间': 'completedAt',
  '创建时间': 'createdAt',
  '周期任务': 'isRecurring',
  '周期规则': 'recurringRule',
  '提前提醒': 'reminderMinutes',
  '标签': 'tagIds',
};

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();
  static const String _backupFormatVersion = '2.0';

  String generateCSV(List<Task> tasks) {
    final buffer = StringBuffer();
    buffer.writeln(
        '﻿ID,标题,内容,状态,优先级,负责人,截止时间,完成时间,创建时间,周期任务,周期规则,提前提醒,标签');
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
        t.isRecurring ? '是' : '否',
        _escape(t.recurringRule ?? ''),
        t.reminderMinutes?.toString() ?? '',
        _escape(t.tagIds.join(' ')),
      ].join(','));
    }
    return buffer.toString();
  }

  /// 解析 CSV 内容为任务 JSON 列表（与 generateCSV 对称）。
  ///
  /// 返回 `{'tasks': [...]}` 格式的 Map，可直接传给 TaskProvider.importData。
  /// 支持引号包裹的字段值（_escape 生成的格式）。
  Map<String, dynamic> parseCSV(String csvContent) {
    final lines = csvContent.split('\n');
    if (lines.isEmpty) return {'tasks': []};

    // 解析表头，建立列索引
    final header = _parseCsvLine(lines.first);
    final colIndex = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      final h = header[i].replaceAll('\ufeff', '').trim(); // 去 BOM
      if (_csvHeaderMap.containsKey(h)) {
        colIndex[_csvHeaderMap[h]!] = i;
      }
    }

    String field(List<String> row, String key) {
      final idx = colIndex[key];
      if (idx == null || idx >= row.length) return '';
      return row[idx].trim();
    }

    final tasks = <Map<String, dynamic>>[];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final row = _parseCsvLine(line);

      final id = field(row, 'id');
      final title = field(row, 'title');
      if (title.isEmpty) continue;

      // status: pending=0, inProgress=1, completed=2, cancelled=3
      final statusName = field(row, 'status');
      final statusMap = {
        'pending': 0, 'inProgress': 1, 'completed': 2, 'cancelled': 3
      };
      // priority: low=0, medium=1, high=2
      final priorityName = field(row, 'priority');
      final priorityMap = {
        'low': 0, 'medium': 1, 'high': 2
      };

      // 时间字段：CSV 可能为空，补默认值满足 fromJson 必需字段要求
      final now = DateTime.now().toIso8601String();
      final createdAt = field(row, 'createdAt');
      final dueTime = field(row, 'dueTime');
      final completedAt = field(row, 'completedAt');

      // 周期任务字段
      final isRecurringStr = field(row, 'isRecurring');
      final isRecurring = isRecurringStr == '是' || isRecurringStr == 'true';
      final recurringRule = field(row, 'recurringRule');
      final reminderStr = field(row, 'reminderMinutes');
      final reminderMinutes = int.tryParse(reminderStr);

      // 标签：CSV 中以空格分隔，转为 JSON 数组
      final tagsStr = field(row, 'tagIds');
      final tagIds = tagsStr.isNotEmpty
          ? jsonEncode(tagsStr.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList())
          : '[]';

      tasks.add({
        'id': id.isNotEmpty ? id : 'imported_${DateTime.now().millisecondsSinceEpoch}_$i',
        'title': title,
        'content': field(row, 'content'),
        'status': statusMap[statusName] ?? 0,
        'priority': priorityMap[priorityName] ?? 1,
        'assignee': field(row, 'assignee'),
        'due_time': dueTime.isNotEmpty ? dueTime : null,
        'completed_at': completedAt.isNotEmpty ? completedAt : null,
        'created_at': createdAt.isNotEmpty ? createdAt : now,
        'updated_at': now,
        'tag_ids': tagIds,
        'attachment_paths': '[]',
        'is_recurring': isRecurring,
        'recurring_rule': recurringRule.isNotEmpty ? recurringRule : null,
        'reminder_minutes': reminderMinutes,
        'version': 1,
      });
    }

    return {'tasks': tasks, 'tags': []};
  }

  /// 解析单行 CSV（支持引号包裹和转义的双引号）
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final sb = StringBuffer();
    bool inQuotes = false;
    int i = 0;
    while (i < line.length) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"'); // 转义的双引号
          i += 2;
          continue;
        }
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
      i++;
    }
    result.add(sb.toString());
    return result;
  }

  /// 生成任务的简化 JSON（保持向后兼容旧格式）。
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

  /// 生成完整备份 JSON（任务全字段 + 标签 + 习惯 + 习惯日志）。
  ///
  /// 这是真正的「数据迁移」格式：包含 tagIds、attachmentPaths、
  /// recurringRule、reminderMinutes 等任务全字段，以及习惯和打卡历史，
  /// 确保导出→导入能无损迁移。
  Future<String> generateFullBackupJSON({
    List<Task>? tasks,
    List<Tag>? tags,
    List<Habit>? habits,
    Map<String, List<HabitLog>>? habitLogs,
  }) async {
    // 从数据库补全未传入的数据
    tasks ??= await DatabaseHelper().getAllTasks();
    tags ??= await DatabaseHelper().getAllTags();
    habits ??= await DatabaseHelper().getAllHabits();
    habitLogs ??= await DatabaseHelper().getAllLogsByDate();

    // 扁平化 habitLogs（Map<String date, List<log>> → List<log>）
    final flatLogs = <Map<String, dynamic>>[];
    for (final entry in habitLogs.values) {
      for (final log in entry) {
        flatLogs.add(log.toJson());
      }
    }

    final backup = {
      'format': 'smart_task_full_backup',
      'version': _backupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'habits': habits.map((h) => h.toJson()).toList(),
      'habitLogs': flatLogs,
    };
    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  Future<void> exportAndShare(List<Task> tasks, {bool asJson = false}) async {
    final dir = await getTemporaryDirectory();
    final ext = asJson ? 'json' : 'csv';
    final content = asJson ? generateJSON(tasks) : generateCSV(tasks);
    final file = File('${dir.path}/tasks_export.$ext');
    await file.writeAsString(content);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: '任务导出'));
  }

  /// 导出完整备份并分享（含任务+标签+习惯+日志）。
  Future<void> exportFullBackupAndShare({
    List<Task>? tasks,
    List<Tag>? tags,
    List<Habit>? habits,
    Map<String, List<HabitLog>>? habitLogs,
  }) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final content = await generateFullBackupJSON(
      tasks: tasks,
      tags: tags,
      habits: habits,
      habitLogs: habitLogs,
    );
    final file = File('${dir.path}/smart_task_backup_$ts.json');
    await file.writeAsString(content);
    await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '智能任务助手完整备份'));
  }

  String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""').replaceAll('\r\n', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ')}"';
    }
    return value;
  }
}
