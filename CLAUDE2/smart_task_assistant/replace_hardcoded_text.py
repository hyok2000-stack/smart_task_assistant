import re

# 读取文件
with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 替换映射
replacements = [
    ("''const Text(\n                        '待处理任务',\n                        style: TextStyle(\n                          fontSize: 18,\n                          fontWeight: FontWeight.w600,\n                          color: Colors.white,\n                        ),\n                      ),''", "''Text(\n                        l.pendingTasks,\n                        style: const TextStyle(\n                          fontSize: 18,\n                          fontWeight: FontWeight.w600,\n                          color: Colors.white,\n                        ),\n                      ),''"),
    
    ("child: const Text('查看全部'),", "child: Text(l.viewAll),"),
    
    ("''const Text(\n                        '所有任务',\n                        style: TextStyle(\n                          fontSize: 24,\n                          fontWeight: FontWeight.bold,\n                        ),\n                      ),''", "''Text(\n                        l.navAll,\n                        style: const TextStyle(\n                          fontSize: 24,\n                          fontWeight: FontWeight.bold,\n                        ),\n                      ),''"),
    
    ("hintText: '搜索任务...',", "hintText: l.searchHint,"),
    
    ("label: const Text('搜索'),", "label: Text(l.search),"),
    
    ("_buildFilterChip('全部', null, provider),", "_buildFilterChip(l.filterAll, null, provider),"),
    
    ("_buildFilterChip(\n                                '待处理', TaskStatus.pending, provider),", "_buildFilterChip(\n                                l.statusPending, TaskStatus.pending, provider),"),
    
    ("_buildFilterChip(\n                                '进行中', TaskStatus.inProgress, provider),", "_buildFilterChip(\n                                l.statusInProgress, TaskStatus.inProgress, provider),"),
    
    ("_buildFilterChip(\n                                '已完成', TaskStatus.completed, provider),", "_buildFilterChip(\n                                l.statusCompleted, TaskStatus.completed, provider),"),
    
    ("_buildFilterChip('已逾期', null, provider,\n                                isOverdue: true),", "_buildFilterChip(l.filterOverdue, null, provider,\n                                isOverdue: true),"),
    
    ("Text(\n              '暂无任务',\n              style: TextStyle(\n                fontSize: 18,\n                fontWeight: FontWeight.w600,\n                color: isWhite\n                    ? AppTheme.textSecondaryColor\n                    : Colors.white.withOpacity(0.9),\n              ),\n            ),", "Text(\n              l.noTasks,\n              style: TextStyle(\n                fontSize: 18,\n                fontWeight: FontWeight.w600,\n                color: isWhite\n                    ? AppTheme.textSecondaryColor\n                    : Colors.white.withOpacity(0.9),\n              ),\n            ),"),
    
    ("Text(\n              '点击右下角按钮添加新任务',\n              style: TextStyle(\n                color: isWhite\n                    ? AppTheme.textHintColor\n                    : Colors.white.withOpacity(0.7),\n              ),\n            ),", "Text(\n              l.addTaskHint,\n              style: TextStyle(\n                color: isWhite\n                    ? AppTheme.textHintColor\n                    : Colors.white.withOpacity(0.7),\n              ),\n            ),"),
    
    ("_buildCompactStatItem(\n                    '已完成', completedCount, AppTheme.successColor),", "_buildCompactStatItem(\n                    l.completedTasks, completedCount, AppTheme.successColor),"),
    
    ("_buildCompactStatItem(\n                    '进行中', inProgressCount, AppTheme.warningColor),", "_buildCompactStatItem(\n                    l.inProgressTasks, inProgressCount, AppTheme.warningColor),"),
    
    ("_buildCompactStatItem('待处理', pendingCount, AppTheme.infoColor),", "_buildCompactStatItem(l.pendingTasksCount, pendingCount, AppTheme.infoColor),"),
    
    ("_buildCompactStatItem(\n                      '逾期', overdueCount, AppTheme.errorColor),", "_buildCompactStatItem(\n                      l.overdueTasksCount, overdueCount, AppTheme.errorColor),"),
    
    ("''const Text(\n                    'AI 智能建议',\n                    style: TextStyle(\n                      fontSize: 13,\n                      fontWeight: FontWeight.w600,\n                      color: Colors.white,\n                      letterSpacing: 0.5,\n                    ),\n                  ),''", "''Text(\n                    l.aiSuggestion,\n                    style: const TextStyle(\n                      fontSize: 13,\n                      fontWeight: FontWeight.w600,\n                      color: Colors.white,\n                      letterSpacing: 0.5,\n                    ),\n                  ),''"),
    
    ("''const Text(\n                        '逾期任务提醒',\n                        style: TextStyle(\n                          fontSize: 18,\n                          fontWeight: FontWeight.bold,\n                        ),\n                      ),''", "''Text(\n                        l.overdueReminder,\n                        style: const TextStyle(\n                          fontSize: 18,\n                          fontWeight: FontWeight.bold,\n                        ),\n                      ),''"),
    
    ("child: Text('暂无逾期任务'),", "child: Text(l.noOverdueTasks),"),
    
    ("subtitle: Text('截止: ${task.dueTimeDescription}'),", "subtitle: Text('${l.deadline}: ${task.dueTimeDescription}'),"),
    
    ("child: const Text('查看'),", "child: Text(l.view),"),
    
    ("_buildDetailRow(\n                          Icons.access_time_rounded,\n                          '截止时间',\n                          task.dueTimeDescription,\n                        ),", "_buildDetailRow(\n                          Icons.access_time_rounded,\n                          l.deadline,\n                          task.dueTimeDescription,\n                        ),"),
    
    ("_buildDetailRow(\n                            Icons.add_circle_outline,\n                            '创建时间',\n                            _formatDateTime(task.createdAt!),\n                          ),", "_buildDetailRow(\n                            Icons.add_circle_outline,\n                            l.createTime,\n                            _formatDateTime(task.createdAt!),\n                          ),"),
    
    ("label: const Text('编辑任务'),", "label: Text(l.editTask),"),
    
    ("''const Text(\n                    '修改状态',\n                    style: TextStyle(\n                      fontSize: 14,\n                      fontWeight: FontWeight.w600,\n                    ),\n                  ),''", "''Text(\n                    l.changeStatus,\n                    style: const TextStyle(\n                      fontSize: 14,\n                      fontWeight: FontWeight.w600,\n                    ),\n                  ),''"),
    
    ("_buildStatusButton(\n                    TaskStatus.pending,\n                    '待处理',\n                    Icons.schedule_rounded,\n                    AppTheme.warningColor,\n                    task,\n                    provider,\n                  ),", "_buildStatusButton(\n                    TaskStatus.pending,\n                    l.statusPending,\n                    Icons.schedule_rounded,\n                    AppTheme.warningColor,\n                    task,\n                    provider,\n                  ),"),
    
    ("_buildStatusButton(\n                    TaskStatus.inProgress,\n                    '进行中',\n                    Icons.play_arrow_rounded,\n                    AppTheme.infoColor,\n                    task,\n                    provider,\n                  ),", "_buildStatusButton(\n                    TaskStatus.inProgress,\n                    l.statusInProgress,\n                    Icons.play_arrow_rounded,\n                    AppTheme.infoColor,\n                    task,\n                    provider,\n                  ),"),
    
    ("_buildStatusButton(\n                    TaskStatus.completed,\n                    '已完成',\n                    Icons.check_circle_rounded,\n                    AppTheme.successColor,\n                    task,\n                    provider,\n                  ),", "_buildStatusButton(\n                    TaskStatus.completed,\n                    l.statusCompleted,\n                    Icons.check_circle_rounded,\n                    AppTheme.successColor,\n                    task,\n                    provider,\n                  ),"),
    
    ("Text('优先级已更改为 ${_getPriorityText(newPriority)}'),", "Text('${l.priority} ${_getPriorityText(newPriority)}'),"),
    
    ("''const Text('修改截止时间',\n                      style:\n                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''", "''Text(l.selectDeadline,\n                      style:\n                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''"),
    
    ("child: const Text('清除时间'),", "child: Text(l.noReminder),"),
    
    ("child: const Text('保存'),", "child: Text(l.save),"),
    
    ("''const Text('提醒时间',\n                      style:\n                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''", "''Text(l.reminder,\n                      style:\n                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''"),
    
    ("child: const Text('关闭提醒'),", "child: Text(l.off),"),
    
    ("''const Text('重复周期',\n                      style:\n                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''", "''Text(l.repeatCycle,\n                      style:\n                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),''"),
    
    ("case TaskPriority.high:\n        return '高优先级';\n      case TaskPriority.medium:\n        return '中优先级';\n      case TaskPriority.low:\n        return '低优先级';", "final l = context.l;\n      switch (priority) {\n        case TaskPriority.high:\n          return l.priorityHigh;\n        case TaskPriority.medium:\n          return l.priorityMedium;\n        case TaskPriority.low:\n          return l.priorityLow;\n      }"),
    
    ("case TaskStatus.pending:\n        return '待处理';\n      case TaskStatus.inProgress:\n        return '进行中';\n      case TaskStatus.completed:\n        return '已完成';\n      case TaskStatus.cancelled:\n        return '已取消';", "final l = context.l;\n      switch (status) {\n        case TaskStatus.pending:\n          return l.statusPending;\n        case TaskStatus.inProgress:\n          return l.statusInProgress;\n        case TaskStatus.completed:\n          return l.statusCompleted;\n        case TaskStatus.cancelled:\n          return l.statusCancelled;\n      }"),
    
    ("Expanded(child: Text('周期任务「${task.title}」已完成，已自动创建下一期')),", "Expanded(child: Text(l.recurringTaskCompleteHint)),"),
    
    ("Text('任务已完成'),", "Text(l.taskComplete),"),
    
    ("title: const Text('确认删除'),", "title: Text(l.confirmDelete),"),
    
    ("content: const Text('确定要删除这个任务吗？此操作不可撤销。'),", "content: Text(l.confirmDeleteHint),"),
    
    ("child: const Text('取消'),", "child: Text(l.cancel),"),
    
    ("child: const Text('删除'),", "child: Text(l.delete),"),
    
    ("Text('任务已删除'),", "Text(l.taskDelete),"),
    
    ("Text('任务已开始'),", "Text(l.taskStart),"),
    
    ("Text('任务已恢复'),", "Text(l.taskRestore),"),
    
    ("''const Text(\n                    '已完成',\n                    style: TextStyle(\n                      fontSize: 16,\n                      fontWeight: FontWeight.w600,\n                    ),\n                  ),''", "''Text(\n                    l.completed,\n                    style: const TextStyle(\n                      fontSize: 16,\n                      fontWeight: FontWeight.w600,\n                    ),\n                  ),''"),
]

# 应用替换
count = 0
for old, new in replacements:
    if old in content:
        content = content.replace(old, new)
        count += 1
        print(f"替换 {count}: {old[:50]}...")

# 写回文件
with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\n总共替换了 {count} 处！')