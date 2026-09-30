import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';
import 'tag_edit_dialog.dart';
import 'distribution_status_widget.dart';
import '../utils/app_localizations.dart';
import '../services/backend_api_service.dart';

/// 任务卡片组件 - 互联网风格设计
class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;
  final VoidCallback? onStart;
  final ValueChanged<TaskStatus>? onStatusChange;
  final ValueChanged<TaskPriority>? onPriorityChange;
  final VoidCallback? onDueTimeTap;
  final VoidCallback? onReminderTap;
  final VoidCallback? onRecurringTap;
  final List<Tag>? availableTags;
  final ValueChanged<List<String>>? onTagsChanged;
  final bool compact;
  final bool selectable;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;
  final bool isDistributed;
  final String? distributionStatus;
  final bool isPinned;
  final VoidCallback? onPinToggle;
  /// 是否启用左滑/右滑操作（完成、删除）。批量选择模式下应置为 false。
  final bool enableSwipeActions;
  /// 「保存为模板」回调（在更多菜单中触发）
  final VoidCallback? onSaveAsTemplate;

  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.onComplete,
    this.onDelete,
    this.onStart,
    this.onStatusChange,
    this.onPriorityChange,
    this.onDueTimeTap,
    this.onReminderTap,
    this.onRecurringTap,
    this.availableTags,
    this.onTagsChanged,
    this.compact = false,
    this.selectable = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.isDistributed = false,
    this.distributionStatus,
    this.isPinned = false,
    this.onPinToggle,
    this.enableSwipeActions = true,
    this.onSaveAsTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final card = compact
        ? _buildCompactCard(context)
        : _buildFullCard(context);

    // 仅当提供了完成/删除回调、非紧凑卡（紧凑卡用于横向滚动，手势会冲突）、
    // 且未处于批量选择态时启用滑动
    final canSwipe = enableSwipeActions &&
        !compact &&
        !selectable &&
        (onComplete != null || onDelete != null);
    if (!canSwipe) return card;

    return _wrapWithSlidable(context, card);
  }

  /// 用 Slidable 包裹卡片，提供滑动完成 / 滑动删除手势。
  Widget _wrapWithSlidable(BuildContext context, Widget child) {
    final l = context.l;
    return Slidable(
      key: ValueKey('task_${task.id}'),
      // 右滑（startToEnd）：完成 / 恢复待办
      startActionPane: onComplete != null
          ? ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.28,
              children: [
                SlidableAction(
                  onPressed: (_) => onComplete?.call(),
                  backgroundColor: AppTheme.successColor,
                  foregroundColor: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  icon: task.isCompleted
                      ? Icons.undo_rounded
                      : Icons.check_rounded,
                  label: task.isCompleted
                      ? l.swipeUndoComplete
                      : l.swipeComplete,
                ),
              ],
            )
          : null,
      // 左滑（endToStart）：开始 / 删除
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: onDelete != null ? 0.56 : 0.28,
        children: [
          if (onStart != null && !task.isCompleted)
            SlidableAction(
              onPressed: (_) => onStart?.call(),
              backgroundColor: AppTheme.infoColor,
              foregroundColor: Colors.white,
              icon: Icons.play_arrow_rounded,
              label: l.swipeStart,
            ),
          if (onDelete != null)
            SlidableAction(
              onPressed: (_) => onDelete?.call(),
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: l.swipeDelete,
            ),
        ],
      ),
      child: child,
    );
  }

  /// 紧凑型卡片 - 用于横向滚动列表
  Widget _buildCompactCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress:
          selectable ? () => onSelectionChanged?.call(!isSelected) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : (isDark
                  ? Colors.grey.shade800
                  : Colors.white.withValues(alpha: 0.95)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (task.isOverdue
                    ? AppTheme.errorColor.withValues(alpha: 0.5)
                    : _getPriorityColor(task.priority).withValues(alpha: 0.3)),
            width: isSelected || task.isOverdue ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.12 : 0.08),
              blurRadius: isSelected ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 完成按钮 - 带动画
            GestureDetector(
              onTap: onComplete,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: task.isCompleted ? 1 : 0),
                duration: const Duration(milliseconds: 350),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 1.0 + value * 0.2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: task.isCompleted
                              ? AppTheme.successColor
                              : _getPriorityColor(task.priority),
                          width: 2,
                        ),
                        color: task.isCompleted
                            ? AppTheme.successColor
                            : Colors.transparent,
                        boxShadow: task.isCompleted && value > 0.5
                            ? [
                                BoxShadow(
                                  color: AppTheme.successColor.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: value > 0.3
                          ? Opacity(
                              opacity: value.clamp(0, 1).toDouble(),
                              child: const Icon(Icons.check, size: 12, color: Colors.white),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            // 优先级颜色条
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: _getPriorityColor(task.priority),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      decoration:
                          task.isCompleted ? TextDecoration.lineThrough : null,
                      color:
                          task.isCompleted ? AppTheme.textSecondaryColor : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // 状态图标
                      _buildCompactStatusIcon(),
                      const SizedBox(width: 6),
                      // 时间
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: task.isOverdue
                            ? AppTheme.errorColor
                            : AppTheme.textHintColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        task.dueTimeDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: task.isOverdue
                              ? AppTheme.errorColor
                              : AppTheme.textSecondaryColor,
                        ),
                      ),
                      // 重复周期图标
                      if (task.isRecurring) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.repeat_rounded,
                          size: 11,
                          color: AppTheme.primaryColor,
                        ),
                      ],
                      // 提醒图标
                      if (task.reminderMinutes != null &&
                          task.reminderMinutes! > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.alarm, size: 11, color: Colors.orange),
                      ],
                      if (isDistributed) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.send_rounded, size: 11, color: AppTheme.primaryColor),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 右侧状态图标
            if (task.isCompleted)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: AppTheme.successColor,
                  size: 14,
                ),
              )
            else if (task.isOverdue)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.errorColor,
                  size: 14,
                ),
              ),
            if (isPinned) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onPinToggle,
                child: const Icon(Icons.push_pin, size: 16, color: AppTheme.primaryColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建紧凑型状态图标
  Widget _buildCompactStatusIcon() {
    Color color;
    IconData icon;

    switch (task.status) {
      case TaskStatus.pending:
        color = AppTheme.warningColor;
        icon = Icons.schedule_rounded;
        break;
      case TaskStatus.inProgress:
        color = AppTheme.infoColor;
        icon = Icons.play_circle_filled_rounded;
        break;
      case TaskStatus.completed:
        color = AppTheme.successColor;
        icon = Icons.check_circle_rounded;
        break;
      case TaskStatus.cancelled:
        color = AppTheme.textHintColor;
        icon = Icons.cancel_rounded;
        break;
    }

    return Icon(icon, size: 11, color: color);
  }

  /// 完整型卡片 - 互联网风格
  Widget _buildFullCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = context.l;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      transform: Matrix4.identity()..scale(isSelected ? 0.98 : 1.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress:
              selectable ? () => onSelectionChanged?.call(!isSelected) : null,
          borderRadius: BorderRadius.circular(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isSelected
                        ? [
                            AppTheme.primaryColor.withValues(alpha: 0.15),
                            AppTheme.primaryColor.withValues(alpha: 0.05),
                          ]
                        : (isDark
                            ? [
                                Colors.white.withValues(alpha: 0.08),
                                Colors.white.withValues(alpha: 0.04),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.95),
                                Colors.white.withValues(alpha: 0.85),
                              ]),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.6)),
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isSelected ? 0.12 : 0.06),
                      blurRadius: isSelected ? 20 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 优先级颜色条
                        Container(
                          width: 4,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _getPriorityColor(task.priority),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 完成按钮 - 带弹性动画
                        GestureDetector(
                          onTap: onComplete,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: task.isCompleted ? 1 : 0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: 1.0 + value * 0.25,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24,
                                  height: 24,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: task.isCompleted
                                          ? AppTheme.successColor
                                          : AppTheme.primaryColor,
                                      width: 2,
                                    ),
                                    color: task.isCompleted
                                        ? AppTheme.successColor
                                        : Colors.transparent,
                                    boxShadow: task.isCompleted && value > 0.5
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.successColor
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: value > 0.3
                                      ? Opacity(
                                          opacity: value.clamp(0, 1).toDouble(),
                                          child: const Icon(
                                            Icons.check,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 任务内容
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 标题
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: task.isCompleted
                                      ? AppTheme.textSecondaryColor
                                      : AppTheme.textPrimaryColor,
                                ),
                                child: Text(
                                  task.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 描述
                              if (task.content != null &&
                                  task.content!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  task.content!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondaryColor,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    height: 1.4,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // 更多操作按钮
                        if (onDelete != null)
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              size: 20,
                              color: AppTheme.textHintColor,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onSelected: (value) {
                              if (value == 'delete') {
                                onDelete?.call();
                              } else if (value == 'edit') {
                                onTap?.call();
                              } else if (value == 'template') {
                                onSaveAsTemplate?.call();
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.edit_outlined,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(l.editTask),
                                  ],
                                ),
                              ),
                              if (onSaveAsTemplate != null)
                                PopupMenuItem(
                                  value: 'template',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.bookmark_add_outlined,
                                        color: AppTheme.infoColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(l.saveAsTemplate),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline,
                                      color: AppTheme.errorColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(l.deleteTask),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 底部信息行
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // 优先级标签
                        _buildPriorityTag(context, task.priority),
                        // 状态标签
                        _buildStatusTag(context, task.status),
                        // 截止时间
                        if (task.dueTime != null) _buildTimeTag(context),
                        // 重复周期
                        if (task.isRecurring) _buildRecurringTag(context),
                        // 提醒时间
                        if (task.reminderMinutes != null &&
                            task.reminderMinutes! > 0)
                          _buildReminderTag(context),
                        // 标签 - 与其他信息同行显示
                        if (availableTags != null &&
                            availableTags!.isNotEmpty &&
                            task.tagIds.isNotEmpty)
                          _buildTaskTags(context),
                        // 已分发标记
                        if (isDistributed) _buildDistributedBadge(context),
                        // 指派给我标记（被指派但非自己创建的任务）
                        if (_isAssignedToMe) _buildAssignedToMeBadge(context),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isAssignedToMe {
    final me = BackendApiService.instance.userId;
    return me != null && task.assigneeUserId == me && task.ownerUserId != me;
  }

  Widget _buildAssignedToMeBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_pin_rounded, size: 11, color: Colors.orange.shade700),
          const SizedBox(width: 3),
          Text('指派给我', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDistributedBadge(BuildContext context) {
    final l = context.l;
    if (distributionStatus != null) {
      return DistributionStatusWidget(status: distributionStatus!, compact: true);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.send_rounded, size: 11, color: AppTheme.primaryColor),
          const SizedBox(width: 3),
          Text(
            l.distributed,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示标签编辑对话框
  void _showTagEditDialog(BuildContext context) {
    if (availableTags == null || availableTags!.isEmpty) {
      return;
    }
    showTagEditDialog(
      context,
      selectedTagIds: task.tagIds,
      availableTags: availableTags!,
      onTagsChanged: (newTagIds) {
        onTagsChanged?.call(newTagIds);
      },
    );
  }

  /// 解析颜色
  Color _parseColor(String hexColor) {
    try {
      hexColor = hexColor.replaceAll('#', '');
      if (hexColor.length == 6) {
        hexColor = 'FF$hexColor';
      }
      return Color(int.parse(hexColor, radix: 16));
    } catch (e) {
      return AppTheme.primaryColor;
    }
  }

  /// 构建优先级标签 - 可点击修改
  Widget _buildPriorityTag(BuildContext context, TaskPriority priority) {
    final l = context.l;
    Color color;
    String label;

    switch (priority) {
      case TaskPriority.high:
        color = AppTheme.errorColor;
        label = l.priorityHighShort;
        break;
      case TaskPriority.medium:
        color = AppTheme.warningColor;
        label = l.priorityMediumShort;
        break;
      case TaskPriority.low:
        color = AppTheme.successColor;
        label = l.priorityLowShort;
        break;
    }

    return GestureDetector(
      onTap: onPriorityChange != null ? () => _showPriorityPicker(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: onPriorityChange != null
              ? Border.all(color: color.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_rounded, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onPriorityChange != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 弹出优先级选择面板（替代原先不可预测的循环点击）
  void _showPriorityPicker(BuildContext context) {
    if (onPriorityChange == null) return;
    final l = context.l;
    final options = <(TaskPriority, String, Color)>[
      (TaskPriority.high, l.priorityHigh, AppTheme.errorColor),
      (TaskPriority.medium, l.priorityMedium, AppTheme.warningColor),
      (TaskPriority.low, l.priorityLow, AppTheme.successColor),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.priority,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...options.map((o) {
                      final isSelected = task.priority == o.$1;
                      return InkWell(
                        onTap: () {
                          onPriorityChange?.call(o.$1);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? o.$3.withValues(alpha: 0.12)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? o.$3 : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.flag_rounded, color: o.$3, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  o.$2,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? o.$3
                                        : AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: o.$3, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建状态标签 - 可点击修改
  Widget _buildStatusTag(BuildContext context, TaskStatus status) {
    final l = context.l;
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case TaskStatus.pending:
        color = AppTheme.warningColor;
        label = l.statusPending;
        icon = Icons.schedule_rounded;
        break;
      case TaskStatus.inProgress:
        color = AppTheme.infoColor;
        label = l.statusInProgress;
        icon = Icons.play_circle_filled_rounded;
        break;
      case TaskStatus.completed:
        color = AppTheme.successColor;
        label = l.statusCompleted;
        icon = Icons.check_circle_rounded;
        break;
      case TaskStatus.cancelled:
        color = AppTheme.textHintColor;
        label = l.statusCancelled;
        icon = Icons.cancel_rounded;
        break;
    }

    return GestureDetector(
      onTap: onStatusChange != null ? () => _showStatusPicker(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: onStatusChange != null
              ? Border.all(color: color.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onStatusChange != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 弹出状态选择面板（替代原先不可预测的循环点击）
  void _showStatusPicker(BuildContext context) {
    if (onStatusChange == null) return;
    final l = context.l;
    final options = <(TaskStatus, String, IconData, Color)>[
      (TaskStatus.pending, l.statusPending, Icons.schedule_rounded, AppTheme.warningColor),
      (TaskStatus.inProgress, l.statusInProgress, Icons.play_circle_filled_rounded, AppTheme.infoColor),
      (TaskStatus.completed, l.statusCompleted, Icons.check_circle_rounded, AppTheme.successColor),
      (TaskStatus.cancelled, l.statusCancelled, Icons.cancel_rounded, AppTheme.textHintColor),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.changeStatus,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...options.map((o) {
                      final isSelected = task.status == o.$1;
                      return InkWell(
                        onTap: () {
                          onStatusChange?.call(o.$1);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? o.$4.withValues(alpha: 0.12)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? o.$4 : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(o.$3, color: o.$4, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  o.$2,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? o.$4
                                        : AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: o.$4, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建时间标签 - 可点击修改
  Widget _buildTimeTag(BuildContext context) {
    final color = task.isOverdue ? AppTheme.errorColor : AppTheme.textHintColor;

    return GestureDetector(
      onTap: onDueTimeTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: task.isOverdue
              ? color.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: onDueTimeTap != null
              ? Border.all(color: color.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              task.dueTimeDescription,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight:
                    task.isOverdue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onDueTimeTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建重复周期标签 - 可点击修改
  Widget _buildRecurringTag(BuildContext context) {
    final l = context.l;
    String label;
    switch (task.recurringRule) {
      case 'daily':
        label = l.dailyRepeat;
        break;
      case 'weekly':
        label = l.weeklyRepeat;
        break;
      case 'monthly':
        label = l.monthlyRepeat;
        break;
      default:
        label = l.recurringCycleShort;
    }

    return GestureDetector(
      onTap: onRecurringTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: onRecurringTap != null
              ? Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.repeat_rounded, size: 11, color: AppTheme.primaryColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRecurringTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.edit,
                size: 8,
                color: AppTheme.primaryColor.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建提醒标签 - 可点击修改
  Widget _buildReminderTag(BuildContext context) {
    final l = context.l;
    String label;
    if (task.reminderMinutes! >= 60) {
      final hours = task.reminderMinutes! ~/ 60;
      label = l.reminderInAdvanceHours(hours);
    } else {
      label = l.reminderInAdvanceMinutes(task.reminderMinutes!);
    }

    return GestureDetector(
      onTap: onReminderTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: onReminderTap != null
              ? Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alarm, size: 11, color: Colors.orange),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onReminderTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: Colors.orange.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建任务标签 - 点击打开标签管理对话框
  Widget _buildTaskTags(BuildContext context) {
    // 只显示任务已关联的标签
    final taskTags =
        availableTags?.where((tag) => task.tagIds.contains(tag.id)).toList() ??
            [];

    if (taskTags.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showTagEditDialog(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: taskTags.map((tag) {
          final color = _parseColor(tag.color);
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.12)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.label_rounded,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.edit, size: 8, color: color.withValues(alpha: 0.8)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return AppTheme.lowPriorityColor;
      case TaskPriority.medium:
        return AppTheme.mediumPriorityColor;
      case TaskPriority.high:
        return AppTheme.highPriorityColor;
    }
  }
}
