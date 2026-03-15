#!/usr/bin/env python3
"""修复SnackBar中的const错误"""

import re

def fix_snackbar_const():
    file_path = 'lib/screens/home_screen.dart'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 修复1: _completeTask中的第二个SnackBar (line ~1899)
    pattern1 = r'(\s+)ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*const\s+SnackBar\(\s*content: const Row\(\s*children: \[\s*Icon\(Icons\.check_circle, color: Colors\.white\),\s*SizedBox\(width: 12\),\s*Text\(l\.taskComplete\),\s*\],\s*\),'
    replacement1 = r'\1ScaffoldMessenger.of(context).showSnackBar(\n\1  SnackBar(\n\1    content: Row(\n\1      children: [\n\1        const Icon(Icons.check_circle, color: Colors.white),\n\1        const SizedBox(width: 12),\n\1        Text(l.taskComplete),\n\1      ],\n\1    ),'
    content = re.sub(pattern1, replacement1, content)
    
    # 修复2: _deleteTask中的SnackBar (line ~1935)
    pattern2 = r'(\s+)ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*const\s+SnackBar\(\s*content: const Row\(\s*children: \[\s*Icon\(Icons\.delete_outline, color: Colors\.white\),\s*SizedBox\(width: 12\),\s*Text\(l\.taskDelete\),\s*\],\s*\),'
    replacement2 = r'\1ScaffoldMessenger.of(context).showSnackBar(\n\1  SnackBar(\n\1    content: Row(\n\1      children: [\n\1        const Icon(Icons.delete_outline, color: Colors.white),\n\1        const SizedBox(width: 12),\n\1        Text(l.taskDelete),\n\1      ],\n\1    ),'
    content = re.sub(pattern2, replacement2, content)
    
    # 修复3: _startTask中的SnackBar (line ~1967)
    pattern3 = r'(\s+)ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*const\s+SnackBar\(\s*content: const Row\(\s*children: \[\s*Icon\(Icons\.play_circle_outline, color: Colors\.white\),\s*SizedBox\(width: 12\),\s*Text\(l\.taskStart\),\s*\],\s*\),'
    replacement3 = r'\1ScaffoldMessenger.of(context).showSnackBar(\n\1  SnackBar(\n\1    content: Row(\n\1      children: [\n\1        const Icon(Icons.play_circle_outline, color: Colors.white),\n\1        const SizedBox(width: 12),\n\1        Text(l.taskStart),\n\1      ],\n\1    ),'
    content = re.sub(pattern3, replacement3, content)
    
    # 修复4: _restoreTask中的SnackBar (line ~2105)
    pattern4 = r'(\s+)ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*const\s+SnackBar\(\s*content: const Row\(\s*children: \[\s*Icon\(Icons\.restore_rounded, color: Colors\.white\),\s*SizedBox\(width: 12\),\s*Text\(l\.taskRestore\),\s*\],\s*\),'
    replacement4 = r'\1ScaffoldMessenger.of(context).showSnackBar(\n\1  SnackBar(\n\1    content: Row(\n\1      children: [\n\1        const Icon(Icons.restore_rounded, color: Colors.white),\n\1        const SizedBox(width: 12),\n\1        Text(l.taskRestore),\n\1      ],\n\1    ),'
    content = re.sub(pattern4, replacement4, content)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ 已修复SnackBar const错误")

if __name__ == '__main__':
    fix_snackbar_const()