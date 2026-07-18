import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';

/// 任务优先级分布饼图（高 / 中 / 低）。
///
/// 用真实的 fl_chart PieChart 替换原先用 LinearProgressIndicator 模拟的横条图，
/// 让占比关系更直观。空数据时显示占位文案。
class PriorityPieChart extends StatelessWidget {
  final int high;
  final int medium;
  final int low;

  const PriorityPieChart({
    super.key,
    required this.high,
    required this.medium,
    required this.low,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final total = high + medium + low;

    // 空状态
    if (total == 0) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            l.isZh ? '暂无任务数据' : 'No task data',
            style: TextStyle(color: AppTheme.textHintColor, fontSize: 13),
          ),
        ),
      );
    }

    return Row(
      children: [
        // 饼图
        SizedBox(
          width: 140,
          height: 140,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: _buildSections(total),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // 图例（含精确数值与百分比）
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegend(
                l.highPriority,
                high,
                total,
                AppTheme.highPriorityColor,
              ),
              const SizedBox(height: 10),
              _buildLegend(
                l.mediumPriority,
                medium,
                total,
                AppTheme.mediumPriorityColor,
              ),
              const SizedBox(height: 10),
              _buildLegend(
                l.lowPriority,
                low,
                total,
                AppTheme.lowPriorityColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(int total) {
    double sectionValue(int v) => total > 0 ? (v / total) * 100 : 0.0;
    return [
      _section(sectionValue(high), AppTheme.highPriorityColor),
      _section(sectionValue(medium), AppTheme.mediumPriorityColor),
      _section(sectionValue(low), AppTheme.lowPriorityColor),
    ];
  }

  PieChartSectionData _section(double value, Color color) {
    return PieChartSectionData(
      value: value,
      color: color,
      radius: 28,
      // 仅在扇区足够大时显示百分比文字，避免拥挤
      title: value > 8 ? '${value.toStringAsFixed(0)}%' : '',
      titleStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildLegend(String label, int count, int total, Color color) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$count ($pct%)',
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
