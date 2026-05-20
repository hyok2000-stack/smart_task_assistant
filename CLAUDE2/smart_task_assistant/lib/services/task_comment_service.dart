import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/task_comment.dart';
import 'backend_api_service.dart';

class TaskCommentService {
  TaskCommentService._();

  static final TaskCommentService instance = TaskCommentService._();
  static const _commentsKey = 'task.comments';

  Future<List<TaskComment>> getComments(String taskId) async {
    return getCommentsForTasks([taskId]);
  }

  Future<List<TaskComment>> getCommentsForTasks(List<String> taskIds) async {
    final ids = taskIds.toSet();
    final comments = await _getAllAndDedup();
    return comments.where((comment) => ids.contains(comment.taskId)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Read all comments, dedup, and persist the cleaned list.
  Future<List<TaskComment>> _getAllAndDedup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_commentsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    final comments = decoded
        .map((json) => TaskComment.fromJson(json as Map<String, dynamic>))
        .toList();

    final deduped = _dedup(comments);
    if (deduped.length != comments.length) {
      // Persist cleaned data
      await prefs.setString(
        _commentsKey,
        jsonEncode(deduped.map((c) => c.toJson()).toList()),
      );
    }
    return deduped;
  }

  Future<List<TaskComment>> getAllComments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_commentsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((json) => TaskComment.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<TaskComment> addLocalComment({
    required String taskId,
    required String content,
  }) async {
    final now = DateTime.now();
    final api = BackendApiService.instance;
    final comment = TaskComment(
      id: const Uuid().v4(),
      taskId: taskId,
      content: content,
      createdAt: now,
      updatedAt: now,
      operationId: const Uuid().v4(),
      authorUserId: api.userId,
      authorName: api.nickname,
    );
    final comments = await getAllComments();
    comments.add(comment);
    await _saveAll(comments);
    return comment;
  }

  Future<void> saveRemoteComments(
      List<BackendTaskComment> remoteComments) async {
    if (remoteComments.isEmpty) return;
    final comments = await getAllComments();
    var changed = false;

    for (final remote in remoteComments) {
      if (remote.status == 'deleted') continue;
      final index = comments.indexWhere(
        (comment) =>
            comment.serverId == remote.id ||
            comment.id == remote.clientCommentId ||
            comment.operationId == remote.operationId ||
            (comment.taskId == remote.taskId &&
             comment.content == remote.content &&
             comment.authorUserId == remote.authorUserId &&
             comment.createdAt.difference(remote.serverCreatedAt).inSeconds.abs() < 60),
      );
      final remoteComment = TaskComment(
        id: remote.clientCommentId,
        taskId: remote.taskId,
        content: remote.content,
        createdAt: remote.serverCreatedAt,
        updatedAt: DateTime.now(),
        operationId: remote.operationId,
        synced: true,
        authorUserId: remote.authorUserId,
        authorName: remote.authorName,
        serverId: remote.id,
      );

      if (index == -1) {
        comments.add(remoteComment);
      } else {
        comments[index] = remoteComment;
      }
      changed = true;
    }

    if (changed) {
      await _saveAll(comments);
    }
  }

  Future<int> syncPendingComments({
    required BackendApiService backend,
    required Future<void> Function(String taskId) ensureTaskSynced,
  }) async {
    if (!backend.isLoggedIn) return 0;
    final comments = await getAllComments();
    final pending = comments.where((comment) => !comment.synced).toList();
    if (pending.isEmpty) return 0;
    var successCount = 0;

    // 先确保所有待同步评论的任务已推送到服务端
    final syncedTaskIds = <String>{};
    final failedTaskIds = <String>{};
    for (final comment in pending) {
      if (syncedTaskIds.contains(comment.taskId) || failedTaskIds.contains(comment.taskId)) continue;
      try {
        await ensureTaskSynced(comment.taskId);
        syncedTaskIds.add(comment.taskId);
      } catch (e) {
        debugPrint('评论所属任务推送失败: $e');
        failedTaskIds.add(comment.taskId);
      }
    }

    // 跳过任务推送失败的评论
    final syncable = pending.where((c) => syncedTaskIds.contains(c.taskId)).toList();

    // 使用批量推送接口
    final batch = syncable
        .map((c) => <String, String>{
              'taskId': c.taskId,
              'content': c.content,
              'clientCommentId': c.id,
              'operationId': c.operationId,
            })
        .toList();

    try {
      await backend.pushCommentsBatch(batch);
      for (final comment in pending) {
        await markSynced(comment.id);
        successCount++;
      }
    } catch (error) {
      // 批量推送失败，回退逐条推送
      for (final comment in syncable) {
        try {
          await backend.addComment(
            taskId: comment.taskId,
            content: comment.content,
            clientCommentId: comment.id,
            operationId: comment.operationId,
          );
          await markSynced(comment.id);
          successCount++;
        } catch (e) {
          await markSyncFailed(comment.id, e);
        }
      }
    }

    return successCount;
  }

  Future<void> markSynced(String id) async {
    await _update(
      id,
      (comment) => comment.copyWith(
        synced: true,
        syncError: null,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markSyncFailed(String id, Object error) async {
    await _update(
      id,
      (comment) => comment.copyWith(
        synced: false,
        syncError: error.toString(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _update(
      String id, TaskComment Function(TaskComment) update) async {
    final comments = await getAllComments();
    final index = comments.indexWhere((comment) => comment.id == id);
    if (index == -1) return;
    comments[index] = update(comments[index]);
    await _saveAll(comments);
  }

  Future<void> _saveAll(List<TaskComment> comments) async {
    final deduped = _dedup(comments);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _commentsKey,
      jsonEncode(deduped.map((comment) => comment.toJson()).toList()),
    );
  }

  /// Robust dedup: removes duplicates keeping the most complete version.
  /// Priority keys: serverId > operationId > (taskId + content + authorUserId)
  static List<TaskComment> _dedup(List<TaskComment> comments) {
    final result = <TaskComment>[];
    // Map from dedup key → index in result
    final serverIdMap = <String, int>{};
    final operationIdMap = <String, int>{};
    final contentKeyMap = <String, int>{};

    for (final c in comments) {
      final contentKey = '${c.taskId}|${c.content}|${c.authorUserId ?? ""}';

      // Check serverId first (most reliable)
      if (c.serverId != null && serverIdMap.containsKey(c.serverId)) {
        final idx = serverIdMap[c.serverId!]!;
        if (_score(c) > _score(result[idx])) {
          result[idx] = _merge(result[idx], c);
          _rebuildKeys(result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
        }
        continue;
      }

      // Check operationId
      if (c.operationId.isNotEmpty && operationIdMap.containsKey(c.operationId)) {
        final idx = operationIdMap[c.operationId]!;
        if (_score(c) > _score(result[idx])) {
          result[idx] = _merge(result[idx], c);
          _rebuildKeys(result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
        }
        continue;
      }

      // Check content key (taskId + content + authorUserId)
      if (contentKeyMap.containsKey(contentKey)) {
        final idx = contentKeyMap[contentKey]!;
        final existing = result[idx];
        // Only treat as duplicate if created within 2 minutes (same content by same user on same task)
        if (c.createdAt.difference(existing.createdAt).inMinutes.abs() < 2) {
          if (_score(c) > _score(existing)) {
            result[idx] = _merge(existing, c);
            _rebuildKeys(result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
          }
          continue;
        }
      }

      // No duplicate found — add new
      final idx = result.length;
      result.add(c);
      if (c.serverId != null) serverIdMap[c.serverId!] = idx;
      if (c.operationId.isNotEmpty) operationIdMap[c.operationId] = idx;
      contentKeyMap[contentKey] = idx;
    }
    return result;
  }

  /// Score: prefer synced and with serverId
  static int _score(TaskComment c) =>
      (c.synced ? 10 : 0) + (c.serverId != null ? 5 : 0) + (c.authorName != null ? 1 : 0);

  /// Merge: combine fields from both, keeping the more complete value
  static TaskComment _merge(TaskComment a, TaskComment b) {
    return a.copyWith(
      serverId: a.serverId ?? b.serverId,
      synced: a.synced || b.synced,
      syncError: a.syncError ?? b.syncError,
      authorName: a.authorName ?? b.authorName,
      authorUserId: a.authorUserId ?? b.authorUserId,
    );
  }

  static void _rebuildKeys(
    TaskComment c,
    int idx,
    Map<String, int> serverIdMap,
    Map<String, int> operationIdMap,
    Map<String, int> contentKeyMap,
  ) {
    if (c.serverId != null) serverIdMap[c.serverId!] = idx;
    if (c.operationId.isNotEmpty) operationIdMap[c.operationId] = idx;
    contentKeyMap['${c.taskId}|${c.content}|${c.authorUserId ?? ""}'] = idx;
  }
}
