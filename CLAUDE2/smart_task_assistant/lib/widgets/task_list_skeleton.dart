import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// 任务列表加载骨架屏。
///
/// 用 shimmer 动画替代裸 CircularProgressIndicator，让列表加载过程
/// 呈现出"内容即将出现"的占位形态，降低用户感知等待时间。
class TaskListSkeleton extends StatelessWidget {
  /// 占位卡片数量
  final int itemCount;

  const TaskListSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade300;
    final highlightColor =
        isDark ? Colors.white.withValues(alpha: 0.16) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView.builder(
        // 骨架屏不可滚动，避免与外层滚动冲突
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) => _buildSkeletonCard(context),
      ),
    );
  }

  Widget _buildSkeletonCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行占位
          Row(
            children: [
              _block(width: 16, height: 16, isCircle: true), // 完成按钮占位
              const SizedBox(width: 12),
              _block(width: 200, height: 14), // 标题占位
              const Spacer(),
              _block(width: 14, height: 14, isCircle: true), // 更多按钮占位
            ],
          ),
          const SizedBox(height: 12),
          // 标签行占位
          Row(
            children: [
              _block(width: 50, height: 20, radius: 10),
              const SizedBox(width: 6),
              _block(width: 60, height: 20, radius: 10),
              const SizedBox(width: 6),
              _block(width: 70, height: 20, radius: 10),
            ],
          ),
        ],
      ),
    );
  }

  Widget _block({
    required double width,
    required double height,
    bool isCircle = false,
    double radius = 4,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white, // shimmer 会覆盖颜色
        borderRadius: isCircle ? null : BorderRadius.circular(radius),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}
