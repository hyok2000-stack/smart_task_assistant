import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smart_task_assistant/database/database_helper.dart';
import 'package:smart_task_assistant/models/task_distribution.dart';
import 'package:uuid/uuid.dart';

/// 任务分发服务
/// 负责管理任务分发的创建、更新和查询
class TaskDistributionService {
  static final TaskDistributionService _instance =
      TaskDistributionService._internal();
  factory TaskDistributionService() => _instance;
  TaskDistributionService._internal();

  final DatabaseHelper _db = DatabaseHelper();

  /// 创建任务分发
  Future<TaskDistribution> create({
    required String taskId,
    required String assigneeName,
    String? assigneeEmail,
    String? assigneePhone,
    String? notes,
    DateTime? dueDate,
  }) async {
    final distribution = TaskDistribution(
      id: const Uuid().v4(),
      taskId: taskId,
      assigneeName: assigneeName,
      assigneeEmail: assigneeEmail,
      assigneePhone: assigneePhone,
      notes: notes,
      dueDate: dueDate,
    );

    await _insertDistribution(distribution);
    return distribution;
  }

  /// 批量创建任务分发
  Future<List<TaskDistribution>> createBatch({
    required String taskId,
    required List<DistributionAssignee> assignees,
    String? notes,
    DateTime? dueDate,
  }) async {
    final distributions = <TaskDistribution>[];

    for (final assignee in assignees) {
      final distribution = TaskDistribution(
        id: const Uuid().v4(),
        taskId: taskId,
        assigneeName: assignee.name,
        assigneeEmail: assignee.email,
        assigneePhone: assignee.phone,
        notes: notes,
        dueDate: dueDate,
      );
      distributions.add(distribution);
    }

    await _insertDistributionsBatch(distributions);
    return distributions;
  }

  /// 接受任务
  Future<TaskDistribution> accept(String id, {String? message}) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final accepted = distribution.accept(message: message);
    await _updateDistribution(accepted);
    return accepted;
  }

  /// 拒绝任务
  Future<TaskDistribution> reject(String id, {String? message}) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final rejected = distribution.reject(message: message);
    await _updateDistribution(rejected);
    return rejected;
  }

  /// 开始任务
  Future<TaskDistribution> start(String id) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final started = distribution.start();
    await _updateDistribution(started);
    return started;
  }

  /// 更新进度
  Future<TaskDistribution> updateProgress(String id, double progress) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final updated = distribution.updateProgress(progress);
    await _updateDistribution(updated);
    return updated;
  }

  /// 完成任务
  Future<TaskDistribution> complete(String id) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final completed = distribution.complete();
    await _updateDistribution(completed);
    return completed;
  }

  /// 取消任务
  Future<TaskDistribution> cancel(String id) async {
    final distribution = await _getDistributionById(id);
    if (distribution == null) {
      throw Exception('分发任务不存在');
    }

    final cancelled = distribution.cancel();
    await _updateDistribution(cancelled);
    return cancelled;
  }

  /// 删除分发
  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete(
      'task_distributions',
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('已删除分发任务: $id');
  }

  /// 批量删除分发
  Future<void> deleteBatch(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _db.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'task_distributions',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// 获取所有分发
  Future<List<TaskDistribution>> getAll() async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_distributions',
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => TaskDistribution.fromJson(map)).toList();
  }

  /// 根据任务ID获取分发
  Future<List<TaskDistribution>> getByTaskId(String taskId) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_distributions',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => TaskDistribution.fromJson(map)).toList();
  }

  /// 根据状态获取分发
  Future<List<TaskDistribution>> getByStatus(DistributionStatus status) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_distributions',
      where: 'status = ?',
      whereArgs: [status.index],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => TaskDistribution.fromJson(map)).toList();
  }

  /// 获取逾期的分发
  Future<List<TaskDistribution>> getOverdue() async {
    final all = await getAll();
    return all.where((d) => d.isOverdue).toList();
  }

  /// 获取即将到期的分发
  Future<List<TaskDistribution>> getDueSoon() async {
    final all = await getAll();
    return all.where((d) => d.isDueSoon).toList();
  }

  /// 获取待确认的分发
  Future<List<TaskDistribution>> getPending() async {
    return getByStatus(DistributionStatus.pending);
  }

  /// 获取进行中的分发
  Future<List<TaskDistribution>> getInProgress() async {
    return getByStatus(DistributionStatus.inProgress);
  }

  /// 获取已完成的分发
  Future<List<TaskDistribution>> getCompleted() async {
    return getByStatus(DistributionStatus.completed);
  }

  String _escapeLike(String input) =>
      input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');

  /// 搜索分发
  Future<List<TaskDistribution>> search(String keyword) async {
    final db = await _db.database;
    final escaped = _escapeLike(keyword);
    final List<Map<String, dynamic>> maps = await db.query(
      'task_distributions',
      where: 'assignee_name LIKE ? OR assignee_email LIKE ? OR notes LIKE ?',
      whereArgs: ['%$escaped%', '%$escaped%', '%$escaped%'],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => TaskDistribution.fromJson(map)).toList();
  }

  /// 获取统计信息
  Future<DistributionStats> getStats() async {
    final all = await getAll();

    final pending =
        all.where((d) => d.status == DistributionStatus.pending).length;
    final accepted =
        all.where((d) => d.status == DistributionStatus.accepted).length;
    final inProgress =
        all.where((d) => d.status == DistributionStatus.inProgress).length;
    final completed =
        all.where((d) => d.status == DistributionStatus.completed).length;
    final rejected =
        all.where((d) => d.status == DistributionStatus.rejected).length;
    final cancelled =
        all.where((d) => d.status == DistributionStatus.cancelled).length;
    final overdue = all.where((d) => d.isOverdue).length;
    final dueSoon = all.where((d) => d.isDueSoon).length;

    return DistributionStats(
      total: all.length,
      pending: pending,
      accepted: accepted,
      inProgress: inProgress,
      completed: completed,
      rejected: rejected,
      cancelled: cancelled,
      overdue: overdue,
      dueSoon: dueSoon,
    );
  }

  // ==================== 私有方法 ====================

  /// 插入分发
  Future<void> _insertDistribution(TaskDistribution distribution) async {
    final db = await _db.database;
    await db.insert(
      'task_distributions',
      _distributionToJson(distribution),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('已创建分发任务: ${distribution.id}');
  }

  /// 批量插入分发
  Future<void> _insertDistributionsBatch(
      List<TaskDistribution> distributions) async {
    final db = await _db.database;
    final batch = db.batch();

    for (final distribution in distributions) {
      batch.insert(
        'task_distributions',
        _distributionToJson(distribution),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint('已批量创建 ${distributions.length} 个分发任务');
  }

  /// 更新分发
  Future<void> _updateDistribution(TaskDistribution distribution) async {
    final db = await _db.database;
    await db.update(
      'task_distributions',
      _distributionToJson(distribution),
      where: 'id = ?',
      whereArgs: [distribution.id],
    );
    debugPrint('已更新分发任务: ${distribution.id}');
  }

  /// 根据ID获取分发
  Future<TaskDistribution?> _getDistributionById(String id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'task_distributions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return TaskDistribution.fromJson(maps.first);
  }

  /// 转换为JSON（适配数据库）
  Map<String, dynamic> _distributionToJson(TaskDistribution distribution) {
    return {
      'id': distribution.id,
      'task_id': distribution.taskId,
      'assignee_name': distribution.assigneeName,
      'assignee_email': distribution.assigneeEmail,
      'assignee_phone': distribution.assigneePhone,
      'status': distribution.status.index,
      'distributed_at': distribution.distributedAt.toIso8601String(),
      'accepted_at': distribution.acceptedAt?.toIso8601String(),
      'completed_at': distribution.completedAt?.toIso8601String(),
      'due_date': distribution.dueDate?.toIso8601String(),
      'notes': distribution.notes,
      'progress': distribution.progress,
      'response_message': distribution.responseMessage,
      'created_at': distribution.createdAt.toIso8601String(),
      'updated_at': distribution.updatedAt.toIso8601String(),
    };
  }
}

/// 分发接收人
class DistributionAssignee {
  final String name;
  final String? email;
  final String? phone;

  DistributionAssignee({
    required this.name,
    this.email,
    this.phone,
  });
}

/// 分发统计信息
class DistributionStats {
  final int total;
  final int pending;
  final int accepted;
  final int inProgress;
  final int completed;
  final int rejected;
  final int cancelled;
  final int overdue;
  final int dueSoon;

  DistributionStats({
    required this.total,
    required this.pending,
    required this.accepted,
    required this.inProgress,
    required this.completed,
    required this.rejected,
    required this.cancelled,
    required this.overdue,
    required this.dueSoon,
  });

  /// 计算完成率
  double get completionRate {
    if (total == 0) return 0.0;
    return (completed / total) * 100;
  }

  /// 计算接受率
  double get acceptanceRate {
    final acceptedTotal = accepted + inProgress + completed;
    if (total == 0) return 0.0;
    return (acceptedTotal / total) * 100;
  }
}
