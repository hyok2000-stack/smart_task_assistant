import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../services/backend_api_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';
import '../widgets/priority_pie_chart.dart';

/// 统计页面
class StatsScreen extends StatelessWidget {
  final VoidCallback? onNavigateToAllTasks;
  final ValueChanged<String>?
      onNavigateToFiltered; // 'pending', 'completed', 'overdue', 'inProgress', 'highPriority'

  const StatsScreen(
      {super.key, this.onNavigateToAllTasks, this.onNavigateToFiltered});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dataStatistics),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 以下卡片由 Consumer 驱动（响应任务数据变化）
            Consumer<TaskProvider>(
              builder: (context, provider, child) {
                final stats = provider.stats;
                final tasks = provider.tasks;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 总览卡片
                    _buildOverviewCard(context, stats, l),
                    const SizedBox(height: 24),
                    // 今日任务统计
                    _buildTodayStatsCard(context, provider, l),
                    const SizedBox(height: 24),
                    // 完成率
                    _buildCompletionRateCard(context, stats, tasks, l),
                    const SizedBox(height: 24),
                    // 逾期任务统计
                    _buildOverdueStatsCard(context, provider, l),
                    const SizedBox(height: 24),
                    // 优先级分布
                    _buildPriorityDistributionCard(context, provider, l),
                    const SizedBox(height: 24),
                    // 标签使用统计
                    _buildTagStatsCard(context, provider, l),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            // 报告生成器——完全独立，不经过 _buildReportCard 包装，确保 State 稳定
            const _ReportGenerator(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
      BuildContext context, Map<String, int> stats, AppLocalizations l) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onNavigateToAllTasks,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withValues(alpha: 0.15),
                AppTheme.secondaryColor.withValues(alpha: 0.15),
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
                l.isZh
                    ? '共 ${stats['total'] ?? 0} 个任务'
                    : '${stats['total'] ?? 0} tasks total',
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
        ),
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
            color: color.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletionRateCard(BuildContext context, Map<String, int> stats,
      List<Task> tasks, AppLocalizations l) {
    final total = stats['total'] ?? 0;
    final completed = stats['completed'] ?? 0;
    final rate =
        total > 0 ? (completed / total * 100).toStringAsFixed(1) : '0.0';

    // 本周 vs 上周完成数趋势（基于 completedAt）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 周一作为一周起点（weekday: 1=周一 ... 7=周日）
    final thisWeekStart = today.subtract(Duration(days: now.weekday - 1));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekStart;
    int completedThisWeek = 0;
    int completedLastWeek = 0;
    for (final t in tasks) {
      if (!t.isCompleted) continue;
      final ca = t.completedAt;
      if (ca == null) continue;
      if (!ca.isBefore(thisWeekStart)) {
        completedThisWeek++;
      } else if (!ca.isBefore(lastWeekStart) && ca.isBefore(lastWeekEnd)) {
        completedLastWeek++;
      }
    }
    final weekDelta = completedThisWeek - completedLastWeek;

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
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      color: AppTheme.successColor.withValues(alpha: 0.1),
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
                    '${l.completedTasks} $completed',
                    style: TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${l.isZh ? "共" : "Total"} $total',
                    style: TextStyle(
                      color: AppTheme.textHintColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 本周完成趋势：本周 N 个，较上周 +/-M
              _buildWeeklyTrendRow(context, completedThisWeek, weekDelta, l),
            ],
          ),
        ),
      ),
    );
  }

  /// 本周完成趋势行：本周完成数 + 与上周的环比
  Widget _buildWeeklyTrendRow(
      BuildContext context, int thisWeek, int delta, AppLocalizations l) {
    final isUp = delta > 0;
    final isDown = delta < 0;
    final trendColor = isUp
        ? AppTheme.successColor
        : (isDown ? AppTheme.errorColor : AppTheme.textHintColor);
    final trendIcon = isUp
        ? Icons.trending_up_rounded
        : (isDown ? Icons.trending_down_rounded : Icons.trending_flat_rounded);
    final trendText = isUp
        ? l.moreThanLastWeek(delta)
        : (isDown ? l.lessThanLastWeek(delta) : l.sameAsLastWeek);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: trendColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(trendIcon, size: 16, color: trendColor),
          const SizedBox(width: 6),
          Text(
            l.completedThisWeek(thisWeek),
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondaryColor,
            ),
          ),
          const Spacer(),
          Text(
            trendText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: trendColor,
            ),
          ),
        ],
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
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      color: AppTheme.infoColor.withValues(alpha: 0.15),
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
                      l.navToday,
                      '${todayTasks.length}',
                      AppTheme.infoColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      l.statusCompleted,
                      '$completedToday',
                      AppTheme.successColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      l.statusPending,
                      '$pendingToday',
                      AppTheme.warningColor,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      l.priorityHigh,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onNavigateToFiltered != null
            ? () => onNavigateToFiltered!('overdue')
            : null,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
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
                    Colors.white.withValues(alpha: 0.9),
                    Colors.white.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
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
                          color: AppTheme.errorColor.withValues(alpha: 0.15),
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
                          l.overdueTasks,
                          '${overdueTasks.length}',
                          AppTheme.errorColor,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          l.priorityHigh,
                          '$highPriorityOverdue',
                          Colors.red.shade700,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          l.isZh ? '紧急处理' : 'Urgent',
                          l.isZh ? '需要关注' : 'Attention',
                          Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
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
                    l.isZh ? '暂无标签数据' : 'No tag data',
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
                    orElse: () => Tag(
                        id: entry.key,
                        name: l.isZh ? '未知标签' : 'Unknown',
                        color: '#999999'),
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
                          '${entry.value}${l.isZh ? "个" : ""}',
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
            color: color.withValues(alpha: 0.1),
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
                Colors.white.withValues(alpha: 0.9),
                Colors.white.withValues(alpha: 0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
              PriorityPieChart(high: high, medium: medium, low: low),
            ],
          ),
        ),
      ),
    );
  }

  // C10: Report generation card
  Widget _buildReportCard(BuildContext context, TaskProvider? provider) {
    final l = context.l;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
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
                child: const Icon(Icons.assessment_rounded,
                    color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(l.isZh ? '数据报告' : 'Data Report',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          const _ReportGenerator(),
        ],
      ),
    );
  }
}

/// 报告生成器——完全独立的 StatefulWidget，不依赖外部 Consumer。
/// 通过 context.read<TaskProvider>() 在生成时获取数据。
class _ReportGenerator extends StatefulWidget {
  const _ReportGenerator();

  @override
  State<_ReportGenerator> createState() => _ReportGeneratorState();
}

class _ReportGeneratorState extends State<_ReportGenerator> {
  Map<String, dynamic>? _report;
  bool _loading = false;
  String _period = 'weekly';
  int _requestId = 0;

  Future<void> _generate() async {
    final requestedPeriod = _period;
    final requestedRange = _reportRange(requestedPeriod);
    final requestId = ++_requestId;
    debugPrint('===== 报告生成开始, period=$requestedPeriod =====');
    setState(() => _loading = true);

    Map<String, dynamic> data;

    try {
      // 尝试从后端获取
      if (BackendApiService.instance.isLoggedIn) {
        final remote = await BackendApiService.instance
            .getReportSummary(
              period: requestedPeriod,
              periodStart: requestedRange.start,
              periodEnd: requestedRange.end,
            )
            .timeout(const Duration(seconds: 5));
        if (remote != null) {
          data = remote;
        } else {
          data = _generateLocalReport(requestedPeriod);
        }
      } else {
        data = _generateLocalReport(requestedPeriod);
      }
    } catch (e) {
      debugPrint('报告生成异常，使用本地数据: $e');
      data = _generateLocalReport(requestedPeriod);
    }

    // 快速切换周期时，忽略已经过期的请求结果。
    if (mounted && requestId == _requestId) {
      setState(() {
        _report = data;
        _loading = false;
      });
      debugPrint('===== 报告生成完成: $data =====');
      // 给一个明确的视觉反馈，方便用户确认点击生效
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_periodLabel(requestedPeriod)} 已生成'),
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'daily':
        return '日报';
      case 'monthly':
        return '月报';
      default:
        return '周报';
    }
  }

  /// 从本地任务数据生成报告
  Map<String, dynamic> _generateLocalReport(String period) {
    final tasks = context.read<TaskProvider>().tasks;
    final range = _reportRange(period);
    final periodTasks = tasks.where((task) {
      final dueInPeriod = task.dueTime != null &&
          !task.dueTime!.isBefore(range.start) &&
          task.dueTime!.isBefore(range.end);
      final completedInPeriod = task.completedAt != null &&
          !task.completedAt!.isBefore(range.start) &&
          task.completedAt!.isBefore(range.end);
      return (!task.createdAt.isBefore(range.start) &&
              task.createdAt.isBefore(range.end)) ||
          completedInPeriod ||
          dueInPeriod;
    }).toList();
    final total = periodTasks.length;
    final completed = periodTasks.where((t) => t.isCompleted).length;
    final inProgress =
        periodTasks.where((t) => t.status == TaskStatus.inProgress).length;
    final overdue =
        periodTasks.where((t) => !t.isCompleted && t.isOverdue).length;
    return {
      'totalTasks': total,
      'completedTasks': completed,
      'inProgressTasks': inProgress,
      'overdueTasks': overdue,
      'completionRate': total > 0 ? (completed / total * 100) : 0,
      'period': period,
      'periodStart': range.start.toIso8601String(),
      'periodEnd': range.end.toIso8601String(),
    };
  }

  DateTimeRange _reportRange(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'daily':
        return DateTimeRange(
            start: today, end: today.add(const Duration(days: 1)));
      case 'monthly':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1),
        );
      default:
        final weekStart =
            today.subtract(Duration(days: today.weekday - DateTime.monday));
        return DateTimeRange(
            start: weekStart, end: weekStart.add(const Duration(days: 7)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _periodChip(context.l.isZh ? '日报' : 'Daily', 'daily'),
              _periodChip(context.l.isZh ? '周报' : 'Weekly', 'weekly'),
              _periodChip(context.l.isZh ? '月报' : 'Monthly', 'monthly'),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : () {
                        debugPrint('报告生成按钮被点击');
                        _generate();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  minimumSize: const Size(80, 44),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(context.l.isZh ? '生成' : 'Generate',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor)),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_periodLabel(_report?['period']?.toString() ?? _period)} · $_reportDateRange',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondaryColor),
                ),
                const SizedBox(height: 8),
                _reportRow(context.l.isZh ? '总任务数' : 'Total Tasks',
                    '${_report!['totalTasks'] ?? 0}'),
                _reportRow(context.l.completedTasks,
                    '${_report!['completedTasks'] ?? 0}'),
                _reportRow(context.l.statusInProgress,
                    '${_report!['inProgressTasks'] ?? 0}'),
                _reportRow(
                    context.l.overdueTasks, '${_report!['overdueTasks'] ?? 0}'),
                _reportRow(context.l.completionRate,
                    '${(_report!['completionRate'] as num? ?? 0).toStringAsFixed(1)}%'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String get _reportDateRange {
    final start =
        DateTime.tryParse(_report?['periodStart']?.toString() ?? '')?.toLocal();
    final end =
        DateTime.tryParse(_report?['periodEnd']?.toString() ?? '')?.toLocal();
    if (start == null || end == null) return '';
    String format(DateTime value) => '${value.month}/${value.day}';
    return '${format(start)} - ${format(end.subtract(const Duration(days: 1)))}';
  }

  Widget _periodChip(String label, String value) {
    final selected = _period == value;
    return GestureDetector(
      onTap: () {
        if (_period == value) return;
        setState(() => _period = value);
        // 切换周期后自动重新生成报告（如果已有数据或之前生成过）
        _generate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: selected ? Border.all(color: AppTheme.primaryColor) : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.textSecondaryColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _reportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondaryColor)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
