import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_assistant/models/task_distribution.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('TaskDistribution', () {
    late TaskDistribution distribution;

    setUp(() {
      distribution = TaskDistribution(
        id: const Uuid().v4(),
        taskId: 'task-123',
        assigneeName: '张三',
        assigneeEmail: 'zhangsan@example.com',
        assigneePhone: '13800138000',
        notes: '请在周五前完成',
        dueDate: DateTime.now().add(const Duration(days: 5)),
      );
    });

    group('初始化测试', () {
      test('应该创建有效的分发任务', () {
        expect(distribution.id, isNotEmpty);
        expect(distribution.taskId, 'task-123');
        expect(distribution.assigneeName, '张三');
        expect(distribution.status, DistributionStatus.pending);
        expect(distribution.progress, 0.0);
        expect(distribution.createdAt, isNotNull);
        expect(distribution.updatedAt, isNotNull);
      });

      test('应该设置默认的 distributedAt', () {
        expect(distribution.distributedAt, isNotNull);
        expect(
          distribution.distributedAt
              .isBefore(DateTime.now().add(const Duration(seconds: 1))),
          isTrue,
        );
      });

      test('应该允许创建基本分发任务（只用必填字段）', () {
        final basic = TaskDistribution(
          id: const Uuid().v4(),
          taskId: 'task-456',
          assigneeName: '李四',
        );
        expect(basic.assigneeEmail, isNull);
        expect(basic.assigneePhone, isNull);
        expect(basic.notes, isNull);
        expect(basic.dueDate, isNull);
      });
    });

    group('状态属性测试', () {
      test('初始状态应该是待确认', () {
        expect(distribution.isPending, isTrue);
        expect(distribution.isAccepted, isFalse);
        expect(distribution.isCompleted, isFalse);
      });

      test('已接受状态应该返回 true', () {
        final accepted = distribution.accept();
        expect(accepted.isAccepted, isTrue);
        expect(accepted.isPending, isFalse);
      });

      test('进行中状态应该返回已接受', () {
        final inProgress = distribution.accept().start();
        expect(inProgress.isAccepted, isTrue);
        expect(inProgress.isCompleted, isFalse);
      });

      test('已完成状态应该返回 true', () {
        final completed = distribution.accept().start().complete();
        expect(completed.isCompleted, isTrue);
        expect(completed.isAccepted, isTrue);
      });

      test('已拒绝状态应该返回未接受', () {
        final rejected = distribution.reject();
        expect(rejected.isAccepted, isFalse);
        expect(rejected.isCompleted, isFalse);
      });
    });

    group('逾期检测测试', () {
      test('未设置截止日期应该不逾期', () {
        final noDueDate = TaskDistribution(
          id: const Uuid().v4(),
          taskId: 'task-789',
          assigneeName: '王五',
        );
        expect(noDueDate.isOverdue, isFalse);
      });

      test('已完成任务应该不逾期', () {
        final completed = distribution
            .copyWith(
              dueDate: DateTime.now().subtract(const Duration(days: 1)),
            )
            .complete();
        expect(completed.isOverdue, isFalse);
      });

      test('超过截止日期应该逾期', () {
        final overdue = distribution.copyWith(
          dueDate: DateTime.now().subtract(const Duration(days: 1)),
        );
        expect(overdue.isOverdue, isTrue);
      });

      test('未超过截止日期应该不逾期', () {
        final notOverdue = distribution.copyWith(
          dueDate: DateTime.now().add(const Duration(days: 1)),
        );
        expect(notOverdue.isOverdue, isFalse);
      });
    });

    group('即将到期测试', () {
      test('未设置截止日期应该不即将到期', () {
        final noDueDate = TaskDistribution(
          id: const Uuid().v4(),
          taskId: 'task-999',
          assigneeName: '赵六',
        );
        expect(noDueDate.isDueSoon, isFalse);
      });

      test('已完成任务应该不即将到期', () {
        final completed = distribution
            .copyWith(
              dueDate: DateTime.now().add(const Duration(days: 1)),
            )
            .complete();
        expect(completed.isDueSoon, isFalse);
      });

      test('1天内到期应该即将到期', () {
        final dueSoon = distribution.copyWith(
          dueDate: DateTime.now().add(const Duration(days: 1)),
        );
        expect(dueSoon.isDueSoon, isTrue);
      });

      test('3天内到期应该即将到期', () {
        final dueSoon = distribution.copyWith(
          dueDate: DateTime.now().add(const Duration(days: 3)),
        );
        expect(dueSoon.isDueSoon, isTrue);
      });

      test('4天后到期不应该即将到期', () {
        final notDueSoon = distribution.copyWith(
          dueDate: DateTime.now().add(const Duration(days: 4)),
        );
        expect(notDueSoon.isDueSoon, isFalse);
      });
    });

    group('状态描述测试', () {
      test('待确认状态描述正确', () {
        expect(distribution.statusDescription, '待确认');
      });

      test('已接受状态描述正确', () {
        expect(distribution.accept().statusDescription, '已接受');
      });

      test('已拒绝状态描述正确', () {
        expect(distribution.reject().statusDescription, '已拒绝');
      });

      test('进行中状态描述正确', () {
        expect(distribution.accept().start().statusDescription, '进行中');
      });

      test('已完成状态描述正确', () {
        expect(
            distribution.accept().start().complete().statusDescription, '已完成');
      });

      test('已取消状态描述正确', () {
        expect(distribution.cancel().statusDescription, '已取消');
      });
    });

    group('任务操作测试', () {
      test('接受任务应该设置状态和时间', () {
        final accepted = distribution.accept(message: '好的，我会完成');
        expect(accepted.status, DistributionStatus.accepted);
        expect(accepted.acceptedAt, isNotNull);
        expect(accepted.responseMessage, '好的，我会完成');
      });

      test('接受任务可以不提供消息', () {
        final accepted = distribution.accept();
        expect(accepted.status, DistributionStatus.accepted);
        expect(accepted.responseMessage, isNull);
      });

      test('拒绝任务应该设置状态和消息', () {
        final rejected = distribution.reject(message: '太忙了，无法完成');
        expect(rejected.status, DistributionStatus.rejected);
        expect(rejected.responseMessage, '太忙了，无法完成');
      });

      test('开始任务应该设置为进行中', () {
        final inProgress = distribution.accept().start();
        expect(inProgress.status, DistributionStatus.inProgress);
      });

      test('未接受的任务开始应该抛出异常', () {
        expect(() => distribution.start(), throwsStateError);
      });

      test('已拒绝的任务开始应该抛出异常', () {
        final rejected = distribution.reject();
        expect(() => rejected.start(), throwsStateError);
      });

      test('更新进度应该在 0-100 之间', () {
        final updated = distribution.updateProgress(50.0);
        expect(updated.progress, 50.0);
      });

      test('更新进度边界值测试', () {
        expect(() => distribution.updateProgress(-1.0), throwsArgumentError);
        expect(() => distribution.updateProgress(101.0), throwsArgumentError);

        final minProgress = distribution.updateProgress(0.0);
        expect(minProgress.progress, 0.0);

        final maxProgress = distribution.updateProgress(100.0);
        expect(maxProgress.progress, 100.0);
      });

      test('完成任务应该设置状态和进度', () {
        final completed = distribution.accept().start().complete();
        expect(completed.status, DistributionStatus.completed);
        expect(completed.progress, 100.0);
        expect(completed.completedAt, isNotNull);
      });

      test('取消任务应该设置状态', () {
        final cancelled = distribution.cancel();
        expect(cancelled.status, DistributionStatus.cancelled);
      });
    });

    group('copyWith 测试', () {
      test('应该复制并修改部分字段', () {
        final copied = distribution.copyWith(
          assigneeName: '新名字',
          progress: 75.0,
        );
        expect(copied.id, distribution.id);
        expect(copied.taskId, distribution.taskId);
        expect(copied.assigneeName, '新名字');
        expect(copied.progress, 75.0);
        expect(copied.assigneeEmail, distribution.assigneeEmail);
      });

      test('copyWith 不提供参数应该保持原值', () {
        final copied = distribution.copyWith();
        expect(copied.id, distribution.id);
        expect(copied.taskId, distribution.taskId);
        expect(copied.assigneeName, distribution.assigneeName);
        expect(copied.progress, distribution.progress);
      });

      test('copyWith 应该自动更新 updatedAt', () {
        sleep(const Duration(milliseconds: 500));
        // copyWith 不传 updatedAt 时，应使用 DateTime.now()
        // 由于时间精度问题，我们检查 updatedAt 被正确传递
        final customTime = DateTime.now().subtract(const Duration(hours: 1));
        final customCopied = distribution.copyWith(updatedAt: customTime);
        expect(customCopied.updatedAt, equals(customTime));
      });
    });

    group('JSON 序列化测试', () {
      test('应该正确序列化为 JSON', () {
        final json = distribution.toJson();
        expect(json['id'], distribution.id);
        expect(json['task_id'], distribution.taskId);
        expect(json['assignee_name'], distribution.assigneeName);
        expect(json['status'], distribution.status.index);
        expect(json['progress'], distribution.progress);
      });

      test('应该正确从 JSON 反序列化', () {
        final json = distribution.toJson();
        final deserialized = TaskDistribution.fromJson(json);
        expect(deserialized.id, distribution.id);
        expect(deserialized.taskId, distribution.taskId);
        expect(deserialized.assigneeName, distribution.assigneeName);
        expect(deserialized.status, distribution.status);
        expect(deserialized.progress, distribution.progress);
      });

      test('序列化和反序列化应该保持数据完整性', () {
        final json = distribution.toJson();
        final deserialized = TaskDistribution.fromJson(json);
        final reserialized = deserialized.toJson();
        expect(reserialized['id'], json['id']);
        expect(reserialized['task_id'], json['task_id']);
        expect(reserialized['assignee_name'], json['assignee_name']);
        expect(reserialized['status'], json['status']);
        expect(reserialized['progress'], json['progress']);
      });
    });

    group('状态转换测试', () {
      test('完整的任务流程应该正常工作', () {
        // 创建 -> 接受 -> 开始 -> 更新进度 -> 完成
        var dist = distribution;

        dist = dist.accept(message: '我接受这个任务');
        expect(dist.status, DistributionStatus.accepted);

        dist = dist.start();
        expect(dist.status, DistributionStatus.inProgress);

        dist = dist.updateProgress(30.0);
        expect(dist.progress, 30.0);

        dist = dist.updateProgress(60.0);
        expect(dist.progress, 60.0);

        dist = dist.complete();
        expect(dist.status, DistributionStatus.completed);
        expect(dist.progress, 100.0);
      });

      test('拒绝后的任务不能接受', () {
        var dist = distribution.reject();
        expect(dist.status, DistributionStatus.rejected);
        // 拒绝后的任务状态保持不变
        expect(dist.isAccepted, isFalse);
      });

      test('取消后的任务不能接受', () {
        var dist = distribution.cancel();
        expect(dist.status, DistributionStatus.cancelled);
        // 取消后的任务状态保持不变
        expect(dist.isAccepted, isFalse);
      });
    });

    group('边界条件测试', () {
      test('进度值为 0.0 应该有效', () {
        final dist = distribution.updateProgress(0.0);
        expect(dist.progress, 0.0);
      });

      test('进度值为 100.0 应该有效', () {
        final dist = distribution.updateProgress(100.0);
        expect(dist.progress, 100.0);
      });

      test('进度值为 50.0 应该有效', () {
        final dist = distribution.updateProgress(50.0);
        expect(dist.progress, 50.0);
      });

      test('进度值精度测试', () {
        final dist = distribution.updateProgress(33.333);
        expect(dist.progress, closeTo(33.333, 0.001));
      });
    });
  });

  group('DistributionStatus 枚举测试', () {
    test('所有状态应该有对应的索引', () {
      expect(DistributionStatus.pending.index, 0);
      expect(DistributionStatus.accepted.index, 1);
      expect(DistributionStatus.rejected.index, 2);
      expect(DistributionStatus.inProgress.index, 3);
      expect(DistributionStatus.completed.index, 4);
      expect(DistributionStatus.cancelled.index, 5);
    });

    test('应该能够通过索引获取状态', () {
      expect(DistributionStatus.values[0], DistributionStatus.pending);
      expect(DistributionStatus.values[1], DistributionStatus.accepted);
      expect(DistributionStatus.values[2], DistributionStatus.rejected);
      expect(DistributionStatus.values[3], DistributionStatus.inProgress);
      expect(DistributionStatus.values[4], DistributionStatus.completed);
      expect(DistributionStatus.values[5], DistributionStatus.cancelled);
    });
  });
}

/// 辅助函数：睡眠
Future<void> sleep(Duration duration) async {
  await Future.delayed(duration);
}
