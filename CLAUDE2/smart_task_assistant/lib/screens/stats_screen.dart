import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../services/backend_api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';

/// 统计页面
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFAFAFA), // 非常浅的灰色，接近白色
            Color(0xFFF8F8F8), // 浅灰
            Color(0xFFF5F5F5), // 稍深的浅灰
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Consumer<TaskProvider>(
        builder: (context, provider, child) {
          final stats = provider.stats;
          final tasks = provider.tasks;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.dataStatistics,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                // 总览卡片
                _buildOverviewCard(context, stats, l),
                const SizedBox(height: 24),
                // 今日任务统计
                _buildTodayStatsCard(context, provider, l),
                const SizedBox(height: 24),
                // 完成率
                _buildCompletionRateCard(context, stats, l),
                const SizedBox(height: 24),
                // 逾期任务统计
                _buildOverdueStatsCard(context, provider, l),
                const SizedBox(height: 24),
                // 优先级分布
                _buildPriorityDistributionCard(context, provider, l),
                const SizedBox(height: 24),
                // 标签使用统计
                _buildTagStatsCard(context, provider, l),
                const SizedBox(height: 24),
                // C10: 生成报告
                _buildReportCard(context, provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverviewCard(
      BuildContext context, Map<String, int> stats, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.15),
            AppTheme.secondaryColor.withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.taskOverview,
            style: TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '共 ${stats['total'] ?? 0} 个任务',
            style: TextStyle(
              color: AppTheme.textPrimaryColor,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildOverviewItem(
                l.statusPending,
                stats['pending'] ?? 0,
                AppTheme.textPrimaryColor,
              ),
              const SizedBox(width: 24),
              _buildOverviewItem(
                l.statusInProgress,
                stats['inProgress'] ?? 0,
                AppTheme.textSecondaryColor,
              ),
              const SizedBox(width: 24),
              _buildOverviewItem(
                l.statusCompleted,
                stats['completed'] ?? 0,
                AppTheme.textHintColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionRateCard(
      BuildContext context, Map<String, int> stats, AppLocalizations l) {
    final total = stats['total'] ?? 0;
    final completed = stats['completed'] ?? 0;
    final rate =
        total > 0 ? (completed / total * 100).toStringAsFixed(1) : '0.0';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l.completionRate,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$rate%',
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total > 0 ? completed / total : 0,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.successColor),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已完成 $completed 个',
                    style: TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '共 $total 个',
                    style: TextStyle(
                      color: AppTheme.textHintColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayStatsCard(
      BuildContext context, TaskProvider provider, AppLocalizations l) {
    final todayTasks = provider.todayTasks;
    final completedToday = todayTasks.where((t) => t.isCompleted).length;
    final pendingToday = todayTasks.where((t) => !t.isCompleted).length;
    final highPriorityToday = todayTasks
        .where((t) => t.priority == TaskPriority.high && !t.isCompleted)
        .length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.infoColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.today_rounded,
                      color: AppTheme.infoColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.navToday,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      '今日任务',
                      '${todayTasks.length}',
                      AppTheme.infoColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '已完成',
                      '$completedToday',
                      AppTheme.successColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '待处理',
                      '$pendingToday',
                      AppTheme.warningColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '高优先级',
                      '$highPriorityToday',
                      AppTheme.errorColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverdueStatsCard(
      BuildContext context, TaskProvider provider, AppLocalizations l) {
    final overdueTasks = provider.overdueTasks;
    final highPriorityOverdue =
        overdueTasks.where((t) => t.priority == TaskPriority.high).length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.errorColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.overdueTasks,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      '逾期任务',
                      '${overdueTasks.length}',
                      AppTheme.errorColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '高优先级',
                      '$highPriorityOverdue',
                      Colors.red.shade700,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '紧急处理',
                      '需要关注',
                      Colors.orange.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagStatsCard(
      BuildContext context, TaskProvider provider, AppLocalizations l) {
    final tasks = provider.tasks;
    final tags = provider.tags;

    // 统计每个标签的任务数量
    final tagStats = <String, int>{};
    for (final task in tasks) {
      for (final tagId in task.tagIds) {
        tagStats[tagId] = (tagStats[tagId] ?? 0) + 1;
      }
    }

    // 按任务数量排序，取前5个
    final sortedTags = tagStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTags = sortedTags.take(5).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.tagManagement,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (topTags.isEmpty)
                Center(
                  child: Text(
                    '暂无标签数据',
                    style: TextStyle(
                      color: AppTheme.textHintColor,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...topTags.map((entry) {
                  final tag = tags.firstWhere(
                    (t) => t.id == entry.key,
                    orElse: () =>
                        Tag(id: entry.key, name: '未知标签', color: '#999999'),
                  );
                  final percentage = tasks.isNotEmpty
                      ? (entry.value / tasks.length * 100).toStringAsFixed(1)
                      : '0.0';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse(tag.color.replaceFirst('#', '0xFF')),
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tag.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          '${entry.value}个',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '($percentage%)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textHintColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityDistributionCard(
      BuildContext context, TaskProvider provider, AppLocalizations l) {
    final tasks = provider.tasks;
    final high = tasks.where((t) => t.priority.index == 2).length;
    final medium = tasks.where((t) => t.priority.index == 1).length;
    final low = tasks.where((t) => t.priority.index == 0).length;
    final total = high + medium + low;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.9),
                Colors.white.withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.priorityDistribution,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              _buildPriorityBar(
                  l.highPriority, high, total, AppTheme.highPriorityColor),
              const SizedBox(height: 12),
              _buildPriorityBar(l.mediumPriority, medium, total,
                  AppTheme.mediumPriorityColor),
              const SizedBox(height: 12),
              _buildPriorityBar(
                  l.lowPriority, low, total, AppTheme.lowPriorityColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBar(String label, int count, int total, Color color) {
    final percentage =
        total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? count / total : 0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // C10: Report generation card
  Widget _buildReportCard(BuildContext context, TaskProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assessment_rounded, color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('数据报告', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          _ReportGenerator(),
        ],
      ),
    );
  }
}

class _ReportGenerator extends StatefulWidget {
  @override
  State<_ReportGenerator> createState() => _ReportGeneratorState();
}

class _ReportGeneratorState extends State<_ReportGenerator> {
  Map<String, dynamic>? _report;
  bool _loading = false;
  String _period = 'weekly';

  Future<void> _generate() async {
    setState(() => _loading = true);

    // 尝试从后端获取，失败则用本地数据
    Map<String, dynamic>? data;
    if (BackendApiService.instance.isLoggedIn) {
      data = await BackendApiService.instance.getReportSummary(period: _period);
    }

    if (data == null) {
      // 本地生成报告
      final provider = Provider.of<TaskProvider>(context, listen: false);
      final tasks = provider.tasks;
      final now = DateTime.now();
      DateTime since;
      if (_period == 'daily') {
        since = now.subtract(const Duration(hours: 24));
      } else if (_period == 'monthly') {
        since = now.subtract(const Duration(days: 30));
      } else {
        since = now.subtract(const Duration(days: 7));
      }
      final total = tasks.length;
      final completed = tasks.where((t) => t.isCompleted).length;
      final inProgress = tasks.where((t) => t.status == TaskStatus.inProgress).length;
      final overdue = tasks.where((t) => !t.isCompleted && t.isOverdue).length;
      data = {
        'totalTasks': total,
        'completedTasks': completed,
        'inProgressTasks': inProgress,
        'overdueTasks': overdue,
        'completionRate': total > 0 ? (completed / total * 100) : 0,
      };
    }

    if (mounted) {
      setState(() {
        _report = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _periodChip('日报', 'daily'),
            const SizedBox(width: 8),
            _periodChip('周报', 'weekly'),
            const SizedBox(width: 8),
            _periodChip('月报', 'monthly'),
            const Spacer(),
            ElevatedButton(
              onPressed: _loading ? null : _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('生成', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
        ),
        if (_report != null && !_loading) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _reportRow('总任务数', '${_report!['totalTasks'] ?? 0}'),
                _reportRow('已完成', '${_report!['completedTasks'] ?? 0}'),
                _reportRow('进行中', '${_report!['inProgressTasks'] ?? 0}'),
                _reportRow('逾期', '${_report!['overdueTasks'] ?? 0}'),
                _reportRow('完成率', '${(_report!['completionRate'] as num? ?? 0).toStringAsFixed(1)}%'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _periodChip(String label, String value) {
    final selected = _period == value;
    return GestureDetector(
      onTap: () => setState(() => _period = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: selected ? Border.all(color: AppTheme.primaryColor) : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: selected ? AppTheme.primaryColor : AppTheme.textSecondaryColor, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _reportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
