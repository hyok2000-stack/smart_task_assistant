import 'package:flutter/foundation.dart';
import 'package:smart_task_assistant/models/task_distribution.dart';
import 'package:smart_task_assistant/services/task_distribution_service.dart';

/// 任务分发状态管理 Provider
class TaskDistributionProvider extends ChangeNotifier {
  final TaskDistributionService _service = TaskDistributionService();

  // 所有分发列表
  List<TaskDistribution> _distributions = [];
  List<TaskDistribution> get distributions => _distributions;

  // 加载状态
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 错误信息
  String? _error;
  String? get error => _error;

  // 统计信息
  DistributionStats? _stats;
  DistributionStats? get stats => _stats;

  /// 加载所有分发
  Future<void> loadDistributions() async {
    _setLoading(true);
    _setError(null);

    try {
      _distributions = await _service.getAll();
      _stats = await _service.getStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('加载分发失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 根据任务ID加载分发
  Future<void> loadByTaskId(String taskId) async {
    _setLoading(true);
    _setError(null);

    try {
      _distributions = await _service.getByTaskId(taskId);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('加载任务分发失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 根据状态加载分发
  Future<void> loadByStatus(DistributionStatus status) async {
    _setLoading(true);
    _setError(null);

    try {
      _distributions = await _service.getByStatus(status);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('加载状态分发失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 创建分发
  Future<TaskDistribution> createDistribution({
    required String taskId,
    required String assigneeName,
    String? assigneeEmail,
    String? assigneePhone,
    String? notes,
    DateTime? dueDate,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final distribution = await _service.create(
        taskId: taskId,
        assigneeName: assigneeName,
        assigneeEmail: assigneeEmail,
        assigneePhone: assigneePhone,
        notes: notes,
        dueDate: dueDate,
      );

      _distributions.insert(0, distribution);
      await _updateStats();
      notifyListeners();
      return distribution;
    } catch (e) {
      _setError(e.toString());
      debugPrint('创建分发失败: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// 批量创建分发
  Future<List<TaskDistribution>> createBatchDistributions({
    required String taskId,
    required List<DistributionAssignee> assignees,
    String? notes,
    DateTime? dueDate,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final distributions = await _service.createBatch(
        taskId: taskId,
        assignees: assignees,
        notes: notes,
        dueDate: dueDate,
      );

      _distributions.insertAll(0, distributions);
      await _updateStats();
      notifyListeners();
      return distributions;
    } catch (e) {
      _setError(e.toString());
      debugPrint('批量创建分发失败: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// 接受任务
  Future<void> acceptDistribution(String id, {String? message}) async {
    _setError(null);

    try {
      final distribution = await _service.accept(id, message: message);
      _updateDistributionInList(distribution);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('接受任务失败: $e');
      rethrow;
    }
  }

  /// 拒绝任务
  Future<void> rejectDistribution(String id, {String? message}) async {
    _setError(null);

    try {
      final distribution = await _service.reject(id, message: message);
      _updateDistributionInList(distribution);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('拒绝任务失败: $e');
      rethrow;
    }
  }

  /// 开始任务
  Future<void> startDistribution(String id) async {
    _setError(null);

    try {
      final distribution = await _service.start(id);
      _updateDistributionInList(distribution);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('开始任务失败: $e');
      rethrow;
    }
  }

  /// 更新进度
  Future<void> updateProgress(String id, double progress) async {
    _setError(null);

    try {
      final distribution = await _service.updateProgress(id, progress);
      _updateDistributionInList(distribution);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('更新进度失败: $e');
      rethrow;
    }
  }

  /// 完成任务
  Future<void> completeDistribution(String id) async {
    _setError(null);

    try {
      final distribution = await _service.complete(id);
      _updateDistributionInList(distribution);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('完成任务失败: $e');
      rethrow;
    }
  }

  /// 取消任务
  Future<void> cancelDistribution(String id) async {
    _setError(null);

    try {
      final distribution = await _service.cancel(id);
      _updateDistributionInList(distribution);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('取消任务失败: $e');
      rethrow;
    }
  }

  /// 删除分发
  Future<void> deleteDistribution(String id) async {
    _setError(null);

    try {
      await _service.delete(id);
      _distributions.removeWhere((d) => d.id == id);
      await _updateStats();
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('删除分发失败: $e');
      rethrow;
    }
  }

  /// 搜索分发
  Future<void> searchDistributions(String keyword) async {
    _setLoading(true);
    _setError(null);

    try {
      _distributions = await _service.search(keyword);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      debugPrint('搜索分发失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// 刷新数据
  Future<void> refresh() async {
    await loadDistributions();
  }

  // ==================== 私有方法 ====================

  /// 更新列表中的分发
  void _updateDistributionInList(TaskDistribution distribution) {
    final index = _distributions.indexWhere((d) => d.id == distribution.id);
    if (index != -1) {
      _distributions[index] = distribution;
    }
  }

  /// 更新统计信息
  Future<void> _updateStats() async {
    try {
      _stats = await _service.getStats();
    } catch (e) {
      debugPrint('更新统计失败: $e');
    }
  }

  /// 设置加载状态
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 设置错误信息
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // ==================== 便捷方法 ====================

  /// 获取待确认的分发
  List<TaskDistribution> get pendingDistributions => _distributions
      .where((d) => d.status == DistributionStatus.pending)
      .toList();

  /// 获取进行中的分发
  List<TaskDistribution> get inProgressDistributions => _distributions
      .where((d) => d.status == DistributionStatus.inProgress)
      .toList();

  /// 获取已完成的分发
  List<TaskDistribution> get completedDistributions => _distributions
      .where((d) => d.status == DistributionStatus.completed)
      .toList();

  /// 获取逾期的分发
  List<TaskDistribution> get overdueDistributions =>
      _distributions.where((d) => d.isOverdue).toList();

  /// 获取即将到期的分发
  List<TaskDistribution> get dueSoonDistributions =>
      _distributions.where((d) => d.isDueSoon).toList();
}
