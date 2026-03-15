import re
import os

# 获取脚本所在目录
script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.join(script_dir, 'lib/screens/home_screen.dart')

# 读取文件
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 替换映射 - 使用正则表达式匹配
replacements = [
    # 筛选器标签
    (r"_buildFilterChip\('全部',", "_buildFilterChip(l.filterAll,"),
    (r"_buildFilterChip\(\s+'待处理', TaskStatus\.pending,", "_buildFilterChip(l.statusPending, TaskStatus.pending,"),
    (r"_buildFilterChip\(\s+'进行中', TaskStatus\.inProgress,", "_buildFilterChip(l.statusInProgress, TaskStatus.inProgress,"),
    (r"_buildFilterChip\(\s+'已完成', TaskStatus\.completed,", "_buildFilterChip(l.statusCompleted, TaskStatus.completed,"),
    (r"_buildFilterChip\('已逾期',", "_buildFilterChip(l.filterOverdue,"),
    
    # 空状态文本
    (r"Text\(\s*'暂无任务',", "Text(l.noTasks,"),
    (r"Text\(\s*'点击右下角按钮添加新任务',", "Text(l.addTaskHint,"),
    
    # 统计标签
    (r"_buildCompactStatItem\(\s*'已完成',", "_buildCompactStatItem(l.completedTasks,"),
    (r"_buildCompactStatItem\(\s*'进行中',", "_buildCompactStatItem(l.inProgressTasks,"),
    (r"_buildCompactStatItem\('待处理',", "_buildCompactStatItem(l.pendingTasksCount,"),
    (r"_buildCompactStatItem\(\s*'逾期',", "_buildCompactStatItem(l.overdueTasksCount,"),
    
    # AI建议卡片
    (r"const Text\(\s*'AI 智能建议',", "Text(l.aiSuggestion,"),
    
    # 逾期提醒对话框
    (r"const Text\(\s*'逾期任务提醒',", "Text(l.overdueReminder,"),
    (r"child: Text\('暂无逾期任务'\),", "child: Text(l.noOverdueTasks),"),
    (r"subtitle: Text\('截止:", "subtitle: Text('${l.deadline}:"),
    (r"child: const Text\('查看'\),", "child: Text(l.view),"),
    
    # 任务详情对话框
    (r"_buildDetailRow\(\s*Icons\.access_time_rounded,\s*'截止时间',", "_buildDetailRow( Icons.access_time_rounded, l.deadline,"),
    (r"_buildDetailRow\(\s*Icons\.add_circle_outline,\s*'创建时间',", "_buildDetailRow( Icons.add_circle_outline, l.createTime,"),
    (r"label: const Text\('编辑任务'\),", "label: Text(l.editTask),"),
    
    # 状态选择器
    (r"const Text\(\s*'修改状态',", "Text(l.changeStatus,"),
    (r"_buildStatusButton\(\s*TaskStatus\.pending,\s*'待处理',", "_buildStatusButton( TaskStatus.pending, l.statusPending,"),
    (r"_buildStatusButton\(\s*TaskStatus\.inProgress,\s*'进行中',", "_buildStatusButton( TaskStatus.inProgress, l.statusInProgress,"),
    (r"_buildStatusButton\(\s*TaskStatus\.completed,\s*'已完成',", "_buildStatusButton( TaskStatus.completed, l.statusCompleted,"),
    
    # 优先级提示
    (r"Text\('优先级已更改为", "Text('${l.priority} "),
    
    # 截止时间对话框
    (r"const Text\('修改截止时间',", "Text(l.selectDeadline,"),
    (r"child: const Text\('清除时间'\),", "child: Text(l.noReminder),"),
    (r"child: const Text\('保存'\),", "child: Text(l.save),"),
    
    # 提醒对话框
    (r"const Text\('提醒时间',", "Text(l.reminder,"),
    (r"child: const Text\('关闭提醒'\),", "child: Text(l.off),"),
    
    # 重复周期对话框
    (r"const Text\('重复周期',", "Text(l.repeatCycle,"),
    
    # 优先级文本
    (r"case TaskPriority\.high:\s+return '高优先级';", "case TaskPriority.high: return l.priorityHigh;"),
    (r"case TaskPriority\.medium:\s+return '中优先级';", "case TaskPriority.medium: return l.priorityMedium;"),
    (r"case TaskPriority\.low:\s+return '低优先级';", "case TaskPriority.low: return l.priorityLow;"),
    
    # 状态文本
    (r"case TaskStatus\.pending:\s+return '待处理';", "case TaskStatus.pending: return l.statusPending;"),
    (r"case TaskStatus\.inProgress:\s+return '进行中';", "case TaskStatus.inProgress: return l.statusInProgress;"),
    (r"case TaskStatus\.completed:\s+return '已完成';", "case TaskStatus.completed: return l.statusCompleted;"),
    (r"case TaskStatus\.cancelled:\s+return '已取消';", "case TaskStatus.cancelled: return l.statusCancelled;"),
    
    # 周期任务提示
    (r"Expanded\(child: Text\('周期任务«.*?»已完成，已自动创建下一期'\)\),", "Expanded(child: Text(l.recurringTaskCompleteHint)),"),
    
    # 任务操作提示
    (r"Text\('任务已完成'\),", "Text(l.taskComplete),"),
    (r"title: const Text\('确认删除'\),", "title: Text(l.confirmDelete),"),
    (r"content: const Text\('确定要删除这个任务吗？此操作不可撤销。'\),", "content: Text(l.confirmDeleteHint),"),
    (r"child: const Text\('取消'\),", "child: Text(l.cancel),"),
    (r"child: const Text\('删除'\),", "child: Text(l.delete),"),
    (r"Text\('任务已删除'\),", "Text(l.taskDelete),"),
    (r"Text\('任务已开始'\),", "Text(l.taskStart),"),
    (r"Text\('任务已恢复'\),", "Text(l.taskRestore),"),
    
    # 已完成部分
    (r"const Text\(\s*'已完成',", "Text(l.completed,"),
]

# 应用替换
count = 0
for pattern, replacement in replacements:
    new_content = re.sub(pattern, replacement, content)
    if new_content != content:
        count += 1
        print(f"替换 {count}: {pattern[:50]}...")
    content = new_content

# 写回文件
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\n总共替换了 {count} 处！')