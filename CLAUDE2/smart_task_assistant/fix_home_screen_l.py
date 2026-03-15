import re
import os

# 获取脚本所在目录
file_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib/screens/home_screen.dart')

# 读取文件
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 需要添加l变量定义的方法列表
methods_to_fix = [
    '_buildEmptyState',
    '_buildProgressCard',
    '_buildAISuggestionCard',
    '_showNotifications',
    '_showTaskDetail',
    '_buildStatusSelector',
    '_buildDetailRow',
    '_getPriorityText',
    '_getStatusText',
    '_changeTaskPriority',
    '_editDueTime',
    '_editReminder',
    '_editRecurring',
    '_completeTask',
    '_deleteTask',
    '_startTask',
    '_restoreTask',
    '_buildCompletedSection',
]

count = 0
for method_name in methods_to_fix:
    # 查找方法定义
    pattern = rf'(Widget {method_name}\([^)]*\) {{|void {method_name}\([^)]*\) {{|String {method_name}\([^)]*\) {{|Color {method_name}\([^)]*\) {{)'
    
    # 检查方法开头10行内是否已有l变量定义
    lines = content.split('\n')
    modified_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        modified_lines.append(line)
        
        # 检查是否是方法定义行
        if re.search(pattern, line):
            # 检查接下来10行是否已有l变量定义
            found_l = False
            for j in range(i+1, min(i+11, len(lines))):
                if 'final l = context.l;' in lines[j] or 'AppLocalizations l = AppLocalizations.of(context)!' in lines[j]:
                    found_l = True
                    break
            
            # 如果没有找到l变量定义，添加它
            if not found_l:
                # 在方法定义后的第一个{后添加
                indent = len(line) - len(line.lstrip())
                indent_str = '  ' * ((indent // 2) + 1)
                modified_lines.append(f'{indent_str}final l = context.l;')
                count += 1
                print(f"已为方法 {method_name} 添加l变量定义")
        
        i += 1
    
    content = '\n'.join(modified_lines)

# 写回文件
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\n总共为 {count} 个方法添加了l变量定义！')