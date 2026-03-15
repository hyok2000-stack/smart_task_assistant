import re
import os

# 获取脚本所在目录
script_dir = os.path.dirname(os.path.abspath(__file__))

# 处理 stats_screen.dart
stats_file = os.path.join(script_dir, 'lib/screens/stats_screen.dart')

# 读取stats_screen.dart
with open(stats_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 添加l变量定义（如果还没有）
if 'final l = context.l;' not in content and 'AppLocalizations l = AppLocalizations.of(context)!' not in content:
    # 在build方法开始处添加l变量
    content = re.sub(
        r'(@override\s+Widget build\(BuildContext context\) \{)',
        r'\1\n    final l = context.l;',
        content
    )

# 替换映射 - stats_screen.dart
stats_replacements = [
    (r"'数据统计',", "l.dataStatistics,"),
    (r"'任务总览',", "l.taskOverview,"),
    (r"'待处理',", "l.statusPending,"),
    (r"'进行中',", "l.statusInProgress,"),
    (r"'已完成',", "l.statusCompleted,"),
    (r"'完成率',", "l.completionRate,"),
    (r"final weekDays = \['周一', '周二', '周三', '周四', '周五', '周六', '周日'\];",
     "final weekDays = [l.monday, l.tuesday, l.wednesday, l.thursday, l.friday, l.saturday, l.sunday];"),
    (r"'本周完成趋势',", "l.weeklyCompletionTrend,"),
    (r"'优先级分布',", "l.priorityDistribution,"),
    (r"_buildPriorityBar\('高优先级',", "_buildPriorityBar(l.highPriority,"),
    (r"_buildPriorityBar\('中优先级',", "_buildPriorityBar(l.mediumPriority,"),
    (r"_buildPriorityBar\('低优先级',", "_buildPriorityBar(l.lowPriority,"),
]

# 应用stats替换
count = 0
for pattern, replacement in stats_replacements:
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE | re.DOTALL)
    if new_content != content:
        count += 1
        print(f"Stats替换 {count}: {pattern[:50]}...")
    content = new_content

# 写回stats_screen.dart
with open(stats_file, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\nStats Screen 总共替换了 {count} 处！')

# 处理 add_task_screen.dart
add_file = os.path.join(script_dir, 'lib/screens/add_task_screen.dart')

# 读取add_task_screen.dart
with open(add_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 添加l变量定义（如果还没有）
if 'final l = context.l;' not in content and 'AppLocalizations l = AppLocalizations.of(context)!' not in content:
    # 在build方法开始处添加l变量
    content = re.sub(
        r'(@override\s+Widget build\(BuildContext context\) \{)',
        r'\1\n    final l = context.l;',
        content
    )

# 替换映射 - add_task_screen.dart
add_replacements = [
    # 提醒选项
    (r"\{'minutes': null, 'label': '不提醒'\}", "{'minutes': null, 'label': l.noReminder}"),
    (r"\{'minutes': 10, 'label': '10分钟前'\}", "{'minutes': 10, 'label': l.minutes10Before}"),
    
    # 默认标签
    (r"name: '工作',", "name: l.tagWork,"),
    (r"name: '个人',", "name: l.tagPersonal,"),
    (r"name: '紧急',", "name: l.tagUrgent,"),
    (r"name: '学习',", "name: l.tagStudy,"),
    
    # 标签类型标题
    (r"'默认标签',", "l.defaultTags,"),
    (r"'自定义标签',", "l.customTags,"),
    
    # 验证提示
    (r"const SnackBar\(content: Text\('请输入任务标题'\)", "SnackBar(content: Text(l.pleaseEnterTitle))"),
    (r"SnackBar\(content: Text\('任务已更新'\)", "SnackBar(content: Text(l.taskUpdated))"),
    
    # 导入对话框中的硬编码
    (r"const Text\('中文'\),", "const Text('中文'),"),  # 保持中文显示
    (r"const Text\('English'\),", "const Text('English'),"),  # 保持英文显示
]

# 应用add_screen替换
add_count = 0
for pattern, replacement in add_replacements:
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE | re.DOTALL)
    if new_content != content:
        add_count += 1
        print(f"Add Task替换 {add_count}: {pattern[:50]}...")
    content = new_content

# 写回add_task_screen.dart
with open(add_file, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\nAdd Task Screen 总共替换了 {add_count} 处！')