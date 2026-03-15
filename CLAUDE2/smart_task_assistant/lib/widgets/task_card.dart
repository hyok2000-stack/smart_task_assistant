import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';
import 'tag_edit_dialog.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactCard(context);
    }
    return _buildFullCard(context);
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
              ? AppTheme.primaryColor.withOpacity(0.15)
              : (isDark
                  ? Colors.grey.shade800
                  : Colors.white.withOpacity(0.95)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (task.isOverdue
                    ? AppTheme.errorColor.withOpacity(0.5)
                    : _getPriorityColor(task.priority).withOpacity(0.3)),
            width: isSelected || task.isOverdue ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.12 : 0.08),
              blurRadius: isSelected ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 完成按钮
            GestureDetector(
              onTap: onComplete,
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
                ),
                child: task.isCompleted
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
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
                          fontSize: 11,
                          color: task.isOverdue
                              ? AppTheme.errorColor
                              : AppTheme.textSecondaryColor,
                        ),
                      ),
                      // 重复周期图标
                      if (task.isRecurring) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.repeat_rounded,
                          size: 11,
                          color: AppTheme.primaryColor,
                        ),
                      ],
                      // 提醒图标
                      if (task.reminderMinutes != null &&
                          task.reminderMinutes! > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.alarm, size: 11, color: Colors.orange),
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
                  color: AppTheme.successColor.withOpacity(0.15),
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
                  color: AppTheme.errorColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.errorColor,
                  size: 14,
                ),
              ),
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
                            AppTheme.primaryColor.withOpacity(0.15),
                            AppTheme.primaryColor.withOpacity(0.05),
                          ]
                        : (isDark
                            ? [
                                Colors.white.withOpacity(0.08),
                                Colors.white.withOpacity(0.04),
                              ]
                            : [
                                Colors.white.withOpacity(0.95),
                                Colors.white.withOpacity(0.85),
                              ]),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : (isDark
                            ? Colors.white.withOpacity(0.15)
                            : Colors.white.withOpacity(0.6)),
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isSelected ? 0.12 : 0.06),
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
                        // 完成按钮
                        GestureDetector(
                          onTap: onComplete,
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
                              boxShadow: task.isCompleted
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.successColor
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: task.isCompleted
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : null,
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
                            icon: Icon(
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
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      color: AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('编辑任务'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: AppTheme.errorColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('删除任务'),
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
                        _buildPriorityTag(task.priority),
                        // 状态标签
                        _buildStatusTag(task.status),
                        // 截止时间
                        if (task.dueTime != null) _buildTimeTag(context),
                        // 重复周期
                        if (task.isRecurring) _buildRecurringTag(),
                        // 提醒时间
                        if (task.reminderMinutes != null &&
                            task.reminderMinutes! > 0)
                          _buildReminderTag(),
                        // 标签 - 与其他信息同行显示
                        if (availableTags != null &&
                            availableTags!.isNotEmpty &&
                            task.tagIds.isNotEmpty)
                          _buildTaskTags(context),
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

  /// 构建标签显示区域 - 只显示任务已关联的标签
  Widget _buildTagsSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 只显示任务已关联的标签
    final taskTags =
        availableTags?.where((tag) => task.tagIds.contains(tag.id)).toList() ??
            [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.label_outline,
                size: 14,
                color: AppTheme.textHintColor,
              ),
              const SizedBox(width: 6),
              Text(
                '标签',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textHintColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // 编辑标签按钮
              GestureDetector(
                onTap: () => _showTagEditDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '编辑',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: taskTags.map((tag) {
              final color = _parseColor(tag.color);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tag.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 切换标签选择
  void _toggleTag(String tagId) {
    final currentTags = List<String>.from(task.tagIds);
    if (currentTags.contains(tagId)) {
      currentTags.remove(tagId);
    } else {
      currentTags.add(tagId);
    }
    onTagsChanged?.call(currentTags);
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
  Widget _buildPriorityTag(TaskPriority priority) {
    Color color;
    String label;

    switch (priority) {
      case TaskPriority.high:
        color = AppTheme.errorColor;
        label = '高';
        break;
      case TaskPriority.medium:
        color = AppTheme.warningColor;
        label = '中';
        break;
      case TaskPriority.low:
        color = AppTheme.successColor;
        label = '低';
        break;
    }

    return GestureDetector(
      onTap: onPriorityChange != null ? () => _showPriorityDialog() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: onPriorityChange != null
              ? Border.all(color: color.withOpacity(0.3), width: 1)
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
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onPriorityChange != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withOpacity(0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 显示优先级选择对话框
  void _showPriorityDialog() {
    // 这里通过 onPriorityChange 回调处理
    // 默认循环切换优先级
    final priorities = [
      TaskPriority.low,
      TaskPriority.medium,
      TaskPriority.high,
    ];
    final currentIndex = priorities.indexOf(task.priority);
    final nextIndex = (currentIndex + 1) % priorities.length;
    onPriorityChange?.call(priorities[nextIndex]);
  }

  /// 构建状态标签 - 可点击修改
  Widget _buildStatusTag(TaskStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case TaskStatus.pending:
        color = AppTheme.warningColor;
        label = '待处理';
        icon = Icons.schedule_rounded;
        break;
      case TaskStatus.inProgress:
        color = AppTheme.infoColor;
        label = '进行中';
        icon = Icons.play_circle_filled_rounded;
        break;
      case TaskStatus.completed:
        color = AppTheme.successColor;
        label = '已完成';
        icon = Icons.check_circle_rounded;
        break;
      case TaskStatus.cancelled:
        color = AppTheme.textHintColor;
        label = '已取消';
        icon = Icons.cancel_rounded;
        break;
    }

    return GestureDetector(
      onTap: onStatusChange != null ? () => _cycleStatus() : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: onStatusChange != null
              ? Border.all(color: color.withOpacity(0.3), width: 1)
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
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onStatusChange != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withOpacity(0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 循环切换状态
  void _cycleStatus() {
    final statuses = [
      TaskStatus.pending,
      TaskStatus.inProgress,
      TaskStatus.completed,
    ];
    final currentIndex = statuses.indexOf(task.status);
    final nextIndex = (currentIndex + 1) % statuses.length;
    onStatusChange?.call(statuses[nextIndex]);
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
              ? color.withOpacity(0.12)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: onDueTimeTap != null
              ? Border.all(color: color.withOpacity(0.3), width: 1)
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
                fontSize: 11,
                color: color,
                fontWeight:
                    task.isOverdue ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onDueTimeTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: color.withOpacity(0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建重复周期标签 - 可点击修改
  Widget _buildRecurringTag() {
    String label;
    switch (task.recurringRule) {
      case 'daily':
        label = '每日';
        break;
      case 'weekly':
        label = '每周';
        break;
      case 'monthly':
        label = '每月';
        break;
      default:
        label = '周期';
    }

    return GestureDetector(
      onTap: onRecurringTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: onRecurringTap != null
              ? Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat_rounded, size: 11, color: AppTheme.primaryColor),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRecurringTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.edit,
                size: 8,
                color: AppTheme.primaryColor.withOpacity(0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建提醒标签 - 可点击修改
  Widget _buildReminderTag() {
    String label;
    if (task.reminderMinutes! >= 60) {
      final hours = task.reminderMinutes! ~/ 60;
      label = '提前$hours小时';
    } else {
      label = '提前${task.reminderMinutes}分钟';
    }

    return GestureDetector(
      onTap: onReminderTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: onReminderTap != null
              ? Border.all(color: Colors.orange.withOpacity(0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm, size: 11, color: Colors.orange),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onReminderTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.edit, size: 8, color: Colors.orange.withOpacity(0.7)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建标签药丸显示
  Widget _buildTagPills(BuildContext context) {
    // 只显示任务已关联的标签
    final taskTags =
        availableTags?.where((tag) => task.tagIds.contains(tag.id)).toList() ??
            [];

    if (taskTags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: taskTags.map((tag) {
        final color = _parseColor(tag.color);
        return GestureDetector(
          onTap: () => _showTagEditDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.18), color.withOpacity(0.12)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.15),
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
                  child: Icon(
                    Icons.label_rounded,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 构建任务标签 - 点击打开标签管理对话框
  Widget _buildTaskTags(BuildContext context) {
    print('===== TaskCard._buildTaskTags =====');
    print('任务ID: ${task.id}');
    print('任务标题: ${task.title}');
    print('任务关联的标签ID: ${task.tagIds}');
    print('可用标签数量: ${availableTags?.length ?? 0}');

    // 只显示任务已关联的标签
    final taskTags =
        availableTags?.where((tag) => task.tagIds.contains(tag.id)).toList() ??
            [];

    print('匹配到的标签数量: ${taskTags.length}');
    for (var tag in taskTags) {
      print('  - 标签ID: ${tag.id}, 名称: ${tag.name}');
    }

    if (taskTags.isEmpty) {
      print('没有匹配的标签，不显示');
      print('====================================');
      return const SizedBox.shrink();
    }
    print('====================================');

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
                colors: [color.withOpacity(0.18), color.withOpacity(0.12)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.15),
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
                  child: Icon(
                    Icons.label_rounded,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.edit, size: 8, color: color.withOpacity(0.8)),
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
