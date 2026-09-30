import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/task.dart';
import 'backend_api_service.dart';

class TaskHistoryEntry {
  final String id;
  final String taskId;
  final String action;
  final String field;
  final String? beforeValue;
  final String? afterValue;
  final String actorName;
  final String? actorUserId;
  final DateTime createdAt;

  const TaskHistoryEntry({
    required this.id,
    required this.taskId,
    required this.action,
    required this.field,
    this.beforeValue,
    this.afterValue,
    required this.actorName,
    this.actorUserId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'action': action,
        'field': field,
        'beforeValue': beforeValue,
        'afterValue': afterValue,
        'actorName': actorName,
        'actorUserId': actorUserId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TaskHistoryEntry(
        id: json['id'] as String,
        taskId: json['taskId'] as String,
        action: json['action'] as String,
        field: json['field'] as String,
        beforeValue: json['beforeValue'] as String?,
        afterValue: json['afterValue'] as String?,
        actorName: json['actorName'] as String? ?? '本机用户',
        actorUserId: json['actorUserId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class TaskHistoryService {
  TaskHistoryService._();
  static final instance = TaskHistoryService._();
  static const _key = 'task.history.v1';
  List<TaskHistoryEntry>? _cache;

  Future<List<TaskHistoryEntry>> _load() async {
    if (_cache != null) return _cache!;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    _cache = raw == null
        ? []
        : (jsonDecode(raw) as List)
            .map((e) => TaskHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
    return _cache!;
  }

  Future<void> _persist() async {
    final entries = await _load();
    // 审计记录保留最近 5000 条，避免无限占用本地存储。
    if (entries.length > 5000) entries.removeRange(0, entries.length - 5000);
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  Future<List<TaskHistoryEntry>> getForTask(String taskId) async {
    final entries = (await _load()).where((e) => e.taskId == taskId).toList();
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> record({
    required String taskId,
    required String action,
    required String field,
    String? beforeValue,
    String? afterValue,
  }) async {
    if (beforeValue == afterValue && action == '编辑') return;
    final api = BackendApiService.instance;
    (await _load()).add(TaskHistoryEntry(
      id: const Uuid().v4(),
      taskId: taskId,
      action: action,
      field: field,
      beforeValue: beforeValue,
      afterValue: afterValue,
      actorName: api.nickname ?? '本机用户',
      actorUserId: api.userId,
      createdAt: DateTime.now(),
    ));
    await _persist();
  }

  Future<void> recordTaskCreated(Task task) => record(
        taskId: task.id,
        action: '创建',
        field: '任务',
        afterValue: task.title,
      );

  Future<void> recordTaskChanges(Task before, Task after) async {
    final changes = <String, (Object?, Object?)>{
      '标题': (before.title, after.title),
      '描述': (before.content, after.content),
      '状态': (before.status.name, after.status.name),
      '优先级': (before.priority.name, after.priority.name),
      '截止时间': (before.dueTime, after.dueTime),
      '指派人': (
        before.assigneeUserId ?? before.assignee,
        after.assigneeUserId ?? after.assignee
      ),
      '附件': (before.attachmentPaths, after.attachmentPaths),
      '父任务': (before.parentId, after.parentId),
      '标签': (before.tagIds, after.tagIds),
    };
    for (final item in changes.entries) {
      final oldText = _display(item.value.$1);
      final newText = _display(item.value.$2);
      if (oldText != newText) {
        final action = item.key == '状态'
            ? '状态变更'
            : item.key == '指派人'
                ? '指派'
                : item.key == '附件'
                    ? '附件变更'
                    : '编辑';
        await record(
          taskId: after.id,
          action: action,
          field: item.key,
          beforeValue: oldText,
          afterValue: newText,
        );
      }
    }
  }

  String? _display(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal().toString().substring(0, 16);
    if (value is List) return value.isEmpty ? '无' : value.join('、');
    final text = value.toString();
    return text.isEmpty ? '无' : text;
  }
}
