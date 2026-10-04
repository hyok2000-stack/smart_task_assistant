import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/task_distribution.dart';
import 'package:uuid/uuid.dart';

// Mock 服务用于测试
class MockTaskDistributionService {
  final List<TaskDistribution> _distributions = [];

  /// 创建任务分发
  TaskDistribution create({
    required String taskId,
    required String assigneeName,
    String? assigneeEmail,
    String? assigneePhone,
    String? notes,
    DateTime? dueDate,
  }) {
    final distribution = TaskDistribution(
      id: const Uuid().v4(),
      taskId: taskId,
      assigneeName: assigneeName,
      assigneeEmail: assigneeEmail,
      assigneePhone: assigneePhone,
      notes: notes,
      dueDate: dueDate,
    );
    _distributions.add(distribution);
    return distribution;
  }

  /// 接受任务
  TaskDistribution accept(String id, {String? message}) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final accepted = _distributions[index].accept(message: message);
    _distributions[index] = accepted;
    return accepted;
  }

  /// 拒绝任务
  TaskDistribution reject(String id, {String? message}) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final rejected = _distributions[index].reject(message: message);
    _distributions[index] = rejected;
    return rejected;
  }

  /// 开始任务
  TaskDistribution start(String id) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final started = _distributions[index].start();
    _distributions[index] = started;
    return started;
  }

  /// 更新进度
  TaskDistribution updateProgress(String id, double progress) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final updated = _distributions[index].updateProgress(progress);
    _distributions[index] = updated;
    return updated;
  }

  /// 完成任务
  TaskDistribution complete(String id) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final completed = _distributions[index].complete();
    _distributions[index] = completed;
    return completed;
  }

  /// 取消任务
  TaskDistribution cancel(String id) {
    final index = _distributions.indexWhere((d) => d.id == id);
    if (index == -1) {
      throw Exception('分发任务不存在');
    }
    final cancelled = _distributions[index].cancel();
    _distributions[index] = cancelled;
    return cancelled;
  }

  /// 获取所有分发
  List<TaskDistribution> getAll() => List.from(_distributions);

  /// 根据任务ID获取分发
  List<TaskDistribution> getByTaskId(String taskId) {
    return _distributions.where((d) => d.taskId == taskId).toList();
  }

  /// 根据状态获取分发
  List<TaskDistribution> getByStatus(DistributionStatus status) {
    return _distributions.where((d) => d.status == status).toList();
  }

  /// 获取逾期的分发
  List<TaskDistribution> getOverdue() {
    return _distributions.where((d) => d.isOverdue).toList();
  }

  /// 获取即将到期的分发
  List<TaskDistribution> getDueSoon() {
    return _distributions.where((d) => d.isDueSoon).toList();
  }

  /// 清空所有分发
  void clear() {
    _distributions.clear();
  }
}

void main() {
  group('TaskDistributionService', () {
    late MockTaskDistributionService service;

    setUp(() {
      service = MockTaskDistributionService();
    });

    group('创建分发测试', () {
      test('应该成功创建任务分发', () {
        final distribution = service.create(
          taskId: 'task-123',
          assigneeName: '张三',
          assigneeEmail: 'zhangsan@example.com',
        );

        expect(distribution.id, isNotEmpty);
        expect(distribution.taskId, 'task-123');
        expect(distribution.assigneeName, '张三');
        expect(distribution.status, DistributionStatus.pending);
        expect(distribution.progress, 0.0);
      });

      test('应该创建多个分发任务', () {
        service.create(taskId: 'task-1', assigneeName: '张三');
        service.create(taskId: 'task-1', assigneeName: '李四');
        service.create(taskId: 'task-2', assigneeName: '王五');

        final all = service.getAll();
        expect(all.length, 3);
      });

      test('应该支持完整的分发信息', () {
        final distribution = service.create(
          taskId: 'task-456',
          assigneeName: '李四',
          assigneeEmail: 'lisi@example.com',
          assigneePhone: '13800138001',
          notes: '请在周五前完成',
          dueDate: DateTime.now().add(const Duration(days: 5)),
        );

        expect(distribution.assigneeEmail, 'lisi@example.com');
        expect(distribution.assigneePhone, '13800138001');
        expect(distribution.notes, '请在周五前完成');
        expect(distribution.dueDate, isNotNull);
      });
    });

    group('接受任务测试', () {
      test('应该成功接受任务', () {
        final distribution = service.create(
          taskId: 'task-789',
          assigneeName: '王五',
        );

        final accepted = service.accept(distribution.id, message: '我接受这个任务');

        expect(accepted.status, DistributionStatus.accepted);
        expect(accepted.acceptedAt, isNotNull);
        expect(accepted.responseMessage, '我接受这个任务');
      });

      test('接受任务可以不提供消息', () {
        final distribution = service.create(
          taskId: 'task-999',
          assigneeName: '赵六',
        );

        final accepted = service.accept(distribution.id);

        expect(accepted.status, DistributionStatus.accepted);
        expect(accepted.responseMessage, isNull);
      });

      test('接受不存在的分发应该抛出异常', () {
        expect(
          () => service.accept('non-existent-id'),
          throwsException,
        );
      });
    });

    group('拒绝任务测试', () {
      test('应该成功拒绝任务', () {
        final distribution = service.create(
          taskId: 'task-111',
          assigneeName: '钱七',
        );

        final rejected = service.reject(distribution.id, message: '太忙了');

        expect(rejected.status, DistributionStatus.rejected);
        expect(rejected.responseMessage, '太忙了');
      });

      test('拒绝任务可以不提供消息', () {
        final distribution = service.create(
          taskId: 'task-222',
          assigneeName: '孙八',
        );

        final rejected = service.reject(distribution.id);

        expect(rejected.status, DistributionStatus.rejected);
        expect(rejected.responseMessage, isNull);
      });
    });

    group('开始任务测试', () {
      test('应该成功开始任务', () {
        final distribution = service.create(
          taskId: 'task-333',
          assigneeName: '周九',
        );

        service.accept(distribution.id);
        final started = service.start(distribution.id);

        expect(started.status, DistributionStatus.inProgress);
      });

      test('未接受的任务开始应该抛出异常', () {
        final distribution = service.create(
          taskId: 'task-444',
          assigneeName: '吴十',
        );

        expect(
          () => service.start(distribution.id),
          throwsStateError,
        );
      });

      test('已拒绝的任务开始应该抛出异常', () {
        final distribution = service.create(
          taskId: 'task-555',
          assigneeName: '郑十一',
        );

        service.reject(distribution.id);
        expect(
          () => service.start(distribution.id),
          throwsStateError,
        );
      });
    });

    group('更新进度测试', () {
      test('应该成功更新进度', () {
        final distribution = service.create(
          taskId: 'task-666',
          assigneeName: '王十二',
        );

        final updated = service.updateProgress(distribution.id, 50.0);

        expect(updated.progress, 50.0);
      });

      test('应该多次更新进度', () {
        final distribution = service.create(
          taskId: 'task-777',
          assigneeName: '李十三',
        );

        service.updateProgress(distribution.id, 25.0);
        service.updateProgress(distribution.id, 50.0);
        service.updateProgress(distribution.id, 75.0);

        final all = service.getAll();
        expect(all.last.progress, 75.0);
      });

      test('更新无效进度应该抛出异常', () {
        final distribution = service.create(
          taskId: 'task-888',
          assigneeName: '张十四',
        );

        expect(
          () => service.updateProgress(distribution.id, -1.0),
          throwsArgumentError,
        );

        expect(
          () => service.updateProgress(distribution.id, 101.0),
          throwsArgumentError,
        );
      });
    });

    group('完成任务测试', () {
      test('应该成功完成任务', () {
        final distribution = service.create(
          taskId: 'task-999',
          assigneeName: '王十五',
        );

        final completed = service.complete(distribution.id);

        expect(completed.status, DistributionStatus.completed);
        expect(completed.progress, 100.0);
        expect(completed.completedAt, isNotNull);
      });

      test('完成任务应该自动设置进度为100', () {
        final distribution = service.create(
          taskId: 'task-000',
          assigneeName: '李十六',
        );

        service.updateProgress(distribution.id, 50.0);
        final completed = service.complete(distribution.id);

        expect(completed.progress, 100.0);
      });
    });

    group('取消任务测试', () {
      test('应该成功取消任务', () {
        final distribution = service.create(
          taskId: 'task-aaa',
          assigneeName: '张十七',
        );

        final cancelled = service.cancel(distribution.id);

        expect(cancelled.status, DistributionStatus.cancelled);
      });

      test('取消进行中的任务应该成功', () {
        final distribution = service.create(
          taskId: 'task-bbb',
          assigneeName: '王十八',
        );

        service.accept(distribution.id);
        service.start(distribution.id);
        final cancelled = service.cancel(distribution.id);

        expect(cancelled.status, DistributionStatus.cancelled);
      });
    });

    group('查询功能测试', () {
      test('应该获取所有分发', () {
        service.create(taskId: 'task-1', assigneeName: '张三');
        service.create(taskId: 'task-2', assigneeName: '李四');
        service.create(taskId: 'task-3', assigneeName: '王五');

        final all = service.getAll();
        expect(all.length, 3);
      });

      test('应该根据任务ID获取分发', () {
        service.create(taskId: 'task-x', assigneeName: '张三');
        service.create(taskId: 'task-x', assigneeName: '李四');
        service.create(taskId: 'task-y', assigneeName: '王五');

        final taskXDistributions = service.getByTaskId('task-x');
        expect(taskXDistributions.length, 2);

        final taskYDistributions = service.getByTaskId('task-y');
        expect(taskYDistributions.length, 1);
      });

      test('应该根据状态获取分发', () {
        final d1 = service.create(taskId: 'task-1', assigneeName: '张三');
        final d2 = service.create(taskId: 'task-2', assigneeName: '李四');
        service.create(taskId: 'task-3', assigneeName: '王五'); // 保持 pending

        service.accept(d1.id);
        service.reject(d2.id);
        // d3 保持 pending

        final pending = service.getByStatus(DistributionStatus.pending);
        final accepted = service.getByStatus(DistributionStatus.accepted);
        final rejected = service.getByStatus(DistributionStatus.rejected);

        expect(pending.length, 1);
        expect(accepted.length, 1);
        expect(rejected.length, 1);
      });

      test('应该获取逾期的分发', () {
        service.create(
          taskId: 'task-1',
          assigneeName: '张三',
          dueDate: DateTime.now().subtract(const Duration(days: 1)),
        );
        service.create(
          taskId: 'task-2',
          assigneeName: '李四',
          dueDate: DateTime.now().add(const Duration(days: 1)),
        );

        final overdue = service.getOverdue();
        expect(overdue.length, 1);
        expect(overdue.first.assigneeName, '张三');
      });

      test('应该获取即将到期的分发', () {
        service.create(
          taskId: 'task-1',
          assigneeName: '张三',
          dueDate: DateTime.now().add(const Duration(days: 2)),
        );
        service.create(
          taskId: 'task-2',
          assigneeName: '李四',
          dueDate: DateTime.now().add(const Duration(days: 5)),
        );

        final dueSoon = service.getDueSoon();
        expect(dueSoon.length, 1);
        expect(dueSoon.first.assigneeName, '张三');
      });
    });

    group('完整流程测试', () {
      test('完整的任务分发流程应该正常工作', () {
        // 1. 创建分发
        final distribution = service.create(
          taskId: 'task-complete',
          assigneeName: '张三',
          assigneeEmail: 'zhangsan@example.com',
          notes: '请在周五前完成',
          dueDate: DateTime.now().add(const Duration(days: 5)),
        );

        expect(distribution.status, DistributionStatus.pending);

        // 2. 接受任务
        var updated = service.accept(distribution.id, message: '我接受这个任务');
        expect(updated.status, DistributionStatus.accepted);

        // 3. 开始任务
        updated = service.start(distribution.id);
        expect(updated.status, DistributionStatus.inProgress);

        // 4. 更新进度
        updated = service.updateProgress(distribution.id, 30.0);
        expect(updated.progress, 30.0);

        updated = service.updateProgress(distribution.id, 60.0);
        expect(updated.progress, 60.0);

        updated = service.updateProgress(distribution.id, 90.0);
        expect(updated.progress, 90.0);

        // 5. 完成任务
        updated = service.complete(distribution.id);
        expect(updated.status, DistributionStatus.completed);
        expect(updated.progress, 100.0);
        expect(updated.completedAt, isNotNull);
      });

      test('拒绝任务流程应该正常工作', () {
        final distribution = service.create(
          taskId: 'task-reject',
          assigneeName: '李四',
          notes: '紧急任务',
        );

        final rejected = service.reject(
          distribution.id,
          message: '由于个人原因无法完成',
        );

        expect(rejected.status, DistributionStatus.rejected);
        expect(rejected.responseMessage, '由于个人原因无法完成');
      });

      test('取消任务流程应该正常工作', () {
        final distribution = service.create(
          taskId: 'task-cancel',
          assigneeName: '王五',
        );

        service.accept(distribution.id);
        service.start(distribution.id);

        final cancelled = service.cancel(distribution.id);
        expect(cancelled.status, DistributionStatus.cancelled);
      });
    });

    group('边界条件测试', () {
      test('应该处理空分发列表', () {
        final all = service.getAll();
        expect(all, isEmpty);
      });

      test('应该处理查询不存在的任务ID', () {
        final distributions = service.getByTaskId('non-existent-task');
        expect(distributions, isEmpty);
      });

      test('应该处理查询不存在的状态', () {
        // 创建一些分发但都是 pending 状态
        service.create(taskId: 'task-1', assigneeName: '张三');
        service.create(taskId: 'task-2', assigneeName: '李四');

        final completed = service.getByStatus(DistributionStatus.completed);
        expect(completed, isEmpty);
      });

      test('应该处理多个分发到同一个任务', () {
        const taskId = 'task-multi';
        service.create(taskId: taskId, assigneeName: '张三');
        service.create(taskId: taskId, assigneeName: '李四');
        service.create(taskId: taskId, assigneeName: '王五');

        service.accept(service.getAll()[0].id);
        service.reject(service.getAll()[1].id);

        final distributions = service.getByTaskId(taskId);
        expect(distributions.length, 3);

        final pending = distributions
            .where((d) => d.status == DistributionStatus.pending)
            .length;
        final accepted = distributions
            .where((d) => d.status == DistributionStatus.accepted)
            .length;
        final rejected = distributions
            .where((d) => d.status == DistributionStatus.rejected)
            .length;

        expect(pending, 1);
        expect(accepted, 1);
        expect(rejected, 1);
      });
    });

    group('清空测试', () {
      test('应该清空所有分发', () {
        service.create(taskId: 'task-1', assigneeName: '张三');
        service.create(taskId: 'task-2', assigneeName: '李四');
        service.create(taskId: 'task-3', assigneeName: '王五');

        expect(service.getAll().length, 3);

        service.clear();

        expect(service.getAll().length, 0);
      });
    });
  });
}
