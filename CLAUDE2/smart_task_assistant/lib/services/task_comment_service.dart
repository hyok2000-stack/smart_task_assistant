import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/task_comment.dart';
import 'backend_api_service.dart';
import 'task_history_service.dart';

class TaskCommentService {
  TaskCommentService._();

  static final TaskCommentService instance = TaskCommentService._();
  static const _commentsKey = 'task.comments';

  // 内存缓存：首次读取后常驻，避免每次 getComments 都重新读 SharedPreferences + 解析 JSON
  List<TaskComment>? _memCache;

  Future<List<TaskComment>> getComments(String taskId) async {
    return getCommentsForTasks([taskId]);
  }

  Future<List<TaskComment>> getCommentsForTasks(List<String> taskIds) async {
    final ids = taskIds.toSet();
    final all = await _loadAll();
    return all
        .where((comment) => ids.contains(comment.taskId) && !comment.deleted)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// 加载全部评论到内存缓存。首次读盘 + 去重 + 持久化清理；后续直接返回内存（毫秒级）。
  Future<List<TaskComment>> _loadAll() async {
    if (_memCache != null) return _memCache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_commentsKey);
    if (raw == null || raw.isEmpty) {
      _memCache = [];
      return _memCache!;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final comments = decoded
        .map((json) => TaskComment.fromJson(json as Map<String, dynamic>))
        .toList();

    final deduped = _dedup(comments);
    _memCache = deduped;
    if (deduped.length != comments.length) {
      // Persist cleaned data
      await prefs.setString(
        _commentsKey,
        jsonEncode(deduped.map((c) => c.toJson()).toList()),
      );
    }
    return _memCache!;
  }

  Future<List<TaskComment>> getAllComments() async {
    return List<TaskComment>.from(await _loadAll());
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
    final all = await _loadAll();
    all.add(comment);
    await _persist(all);
    await TaskHistoryService.instance.record(
      taskId: taskId,
      action: '评论',
      field: '评论',
      afterValue: content,
    );
    return comment;
  }

  Future<void> saveRemoteComments(
      List<BackendTaskComment> remoteComments) async {
    if (remoteComments.isEmpty) return;
    final all = await _loadAll();
    var changed = false;

    for (final remote in remoteComments) {
      if (remote.status == 'deleted') {
        // 远端已删除 → 同步删除本地对应评论（多端删除一致）
        final before = all.length;
        all.removeWhere((c) =>
            c.serverId == remote.id ||
            c.id == remote.clientCommentId ||
            c.operationId == remote.operationId);
        if (all.length != before) changed = true;
        continue;
      }
      // 本地已软删除（墓碑）→ 跳过拉回，保持删除意图，等待向服务端 DELETE
      final tombstoned = all.any((c) =>
          c.deleted &&
          (c.serverId == remote.id ||
              c.id == remote.clientCommentId ||
              c.operationId == remote.operationId));
      if (tombstoned) continue;
      final index = all.indexWhere(
        (comment) =>
            comment.serverId == remote.id ||
            comment.id == remote.clientCommentId ||
            comment.operationId == remote.operationId ||
            (comment.taskId == remote.taskId &&
                comment.content == remote.content &&
                comment.authorUserId == remote.authorUserId &&
                comment.createdAt
                        .difference(remote.serverCreatedAt)
                        .inSeconds
                        .abs() <
                    60),
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
        all.add(remoteComment);
      } else {
        all[index] = remoteComment;
      }
      changed = true;
    }

    if (changed) {
      await _persist(all);
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

    // 分类：待删除（墓碑+已同步）/ 待编辑（已同步，内容变更）/ 待新增（纯本地）
    final toDelete =
        pending.where((c) => c.deleted && c.serverId != null).toList();
    final toEdit =
        pending.where((c) => !c.deleted && c.serverId != null).toList();
    final toAdd =
        pending.where((c) => !c.deleted && c.serverId == null).toList();

    // 缓存任务同步结果，避免同一任务重复推送
    final syncedTaskIds = <String>{};
    final failedTaskIds = <String>{};

    Future<bool> ensureSynced(String taskId) async {
      if (syncedTaskIds.contains(taskId)) return true;
      if (failedTaskIds.contains(taskId)) return false;
      try {
        await ensureTaskSynced(taskId);
        syncedTaskIds.add(taskId);
        return true;
      } catch (e) {
        debugPrint('评论所属任务推送失败: $e');
        failedTaskIds.add(taskId);
        return false;
      }
    }

    // 1. 同步删除（向服务端 DELETE，成功后清除本地墓碑）
    for (final comment in toDelete) {
      if (!await ensureSynced(comment.taskId)) continue;
      try {
        await backend.deleteComment(
          taskId: comment.taskId,
          commentId: comment.serverId!,
        );
        await hardDeleteComment(comment.id);
        successCount++;
      } catch (e) {
        debugPrint('评论删除同步失败: $e');
      }
    }

    // 2. 同步编辑（向服务端 PATCH，成功后标记已同步）
    for (final comment in toEdit) {
      if (!await ensureSynced(comment.taskId)) continue;
      try {
        await backend.editComment(
          taskId: comment.taskId,
          commentId: comment.serverId!,
          content: comment.content,
        );
        await markSynced(comment.id);
        successCount++;
      } catch (e) {
        await markSyncFailed(comment.id, e);
      }
    }

    // 3. 同步新增（批量推送）
    if (toAdd.isNotEmpty) {
      for (final comment in toAdd) {
        await ensureSynced(comment.taskId);
      }
      final syncable =
          toAdd.where((c) => syncedTaskIds.contains(c.taskId)).toList();
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
        for (final comment in syncable) {
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

  /// 创建评论 push 成功后，回填服务端真实 id（serverId）并标记已同步。
  /// 必须回填，否则后续编辑/删除会用本地 clientCommentId 调后端导致 404。
  Future<void> attachServerId(String localId, String serverId) async {
    await _update(
      localId,
      (comment) => comment.copyWith(
        serverId: serverId,
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
    await _updateReturning(id, update);
  }

  /// 与 [_update] 相同，但返回更新后的对象（找不到时返回 null）。
  Future<TaskComment?> _updateReturning(
      String id, TaskComment Function(TaskComment) update) async {
    final all = await _loadAll();
    final index = all.indexWhere((comment) => comment.id == id);
    if (index == -1) return null;
    final updated = update(all[index]);
    all[index] = updated;
    await _persist(all);
    return updated;
  }

  /// 编辑本地评论：落库并标记为待同步（synced=false）。
  /// 在线时由调用方立即 PATCH 后端；离线则由 syncPendingComments 重试。
  Future<TaskComment?> editLocalComment(String id, String content) async {
    final all = await _loadAll();
    final oldIndex = all.indexWhere((comment) => comment.id == id);
    final old = oldIndex < 0 ? null : all[oldIndex];
    final updated = await _updateReturning(
      id,
      (c) => c.copyWith(
        content: content,
        updatedAt: DateTime.now(),
        synced: false,
        syncError: null,
      ),
    );
    if (old != null && updated != null && old.content != content) {
      await TaskHistoryService.instance.record(
        taskId: old.taskId,
        action: '编辑评论',
        field: '评论',
        beforeValue: old.content,
        afterValue: content,
      );
    }
    return updated;
  }

  /// 删除本地评论。
  /// - 纯本地评论（无 serverId，后端不存在）：直接硬删除。
  /// - 已同步评论（有 serverId）：软删除（置墓碑 deleted=true，synced=false），
  ///   等待 syncPendingComments 向后端 DELETE；DELETE 成功后由 [hardDeleteComment] 清除墓碑。
  Future<void> deleteLocalComment(String id) async {
    final all = await _loadAll();
    final index = all.indexWhere((comment) => comment.id == id);
    if (index == -1) return;
    final comment = all[index];
    if (comment.serverId == null) {
      all.removeAt(index);
    } else {
      all[index] = comment.copyWith(
        deleted: true,
        synced: false,
        updatedAt: DateTime.now(),
      );
    }
    await _persist(all);
    await TaskHistoryService.instance.record(
      taskId: comment.taskId,
      action: '删除评论',
      field: '评论',
      beforeValue: comment.content,
      afterValue: '已删除',
    );
  }

  /// 硬删除：从存储中彻底移除（用于后端 DELETE 成功后清除墓碑）。
  Future<void> hardDeleteComment(String id) async {
    final all = await _loadAll();
    all.removeWhere((comment) => comment.id == id);
    await _persist(all);
  }

  /// 持久化并同步更新内存缓存
  Future<void> _persist(List<TaskComment> comments) async {
    final deduped = _dedup(comments);
    _memCache = deduped;
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
          _rebuildKeys(
              result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
        }
        continue;
      }

      // Check operationId
      if (c.operationId.isNotEmpty &&
          operationIdMap.containsKey(c.operationId)) {
        final idx = operationIdMap[c.operationId]!;
        if (_score(c) > _score(result[idx])) {
          result[idx] = _merge(result[idx], c);
          _rebuildKeys(
              result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
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
            _rebuildKeys(
                result[idx], idx, serverIdMap, operationIdMap, contentKeyMap);
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

  /// Score: prefer synced and with serverId；墓碑(deleted)权重最高，确保删除意图不被覆盖
  static int _score(TaskComment c) =>
      (c.deleted ? 1000 : 0) +
      (c.synced ? 10 : 0) +
      (c.serverId != null ? 5 : 0) +
      (c.authorName != null ? 1 : 0);

  /// Merge: combine fields from both, keeping the more complete value
  static TaskComment _merge(TaskComment a, TaskComment b) {
    return a.copyWith(
      serverId: a.serverId ?? b.serverId,
      synced: a.synced || b.synced,
      syncError: a.syncError ?? b.syncError,
      authorName: a.authorName ?? b.authorName,
      authorUserId: a.authorUserId ?? b.authorUserId,
      deleted: a.deleted || b.deleted,
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
