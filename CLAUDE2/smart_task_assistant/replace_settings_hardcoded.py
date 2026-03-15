import re
import os

# 获取脚本所在目录
script_dir = os.path.dirname(os.path.abspath(__file__))
file_path = os.path.join(script_dir, 'lib/screens/settings_screen.dart')

# 读取文件
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 替换映射 - 使用正则表达式匹配
replacements = [
    # 默认标签名称
    (r"name: '工作',", "name: l.tagWork,"),
    (r"name: '个人',", "name: l.tagPersonal,"),
    (r"name: '紧急',", "name: l.tagUrgent,"),
    (r"name: '学习',", "name: l.tagStudy,"),
    
    # 语言选择对话框
    (r"title: Text\(settings\.isZh \? '选择语言' : 'Select Language'\),", "title: Text(l.selectLanguage),"),
    (r"title: const Text\('中文'\),", "title: const Text('中文'),"),  # 保持中文显示
    (r"title: const Text\('English'\),", "title: const Text('English'),"),  # 保持英文显示
    
    # 标签默认标记
    (r"child: Text\(\s*l\.isZh \? '默认' : 'Default'\s*\),", "child: Text(l.defaultTag),"),
    
    # 导出成功的提示
    (r"Text\('✓ 已导out \$\{tasks\.length\} 个任务和 \$\{tags\.length\} 个标签'\),", 
     "Text('${l.exportedCount} ${tasks.length}${l.tasksAndTags}${tags.length}${l.tags}'),"),
    (r"Text\(\s*'提示：请在下载目录创建 databack 文件夹，并将文件移动到该文件夹中'", 
     "Text(l.exportHint"),
    (r"Text\(\s*'保存位置: \$\{file\.path\}'", 
     "Text('${l.saveLocation}: ${file.path}'"),
    (r"SnackBar\(content: Text\('导出失败: \$e'\)", 
     "SnackBar(content: Text('${l.exportFailed}: $e')"),
    
    # 导入失败的提示
    (r"SnackBar\(content: Text\('导入失败: \$e'\)", 
     "SnackBar(content: Text('${l.importFailed}: $e')"),
    
    # 导入数据时的各种提示
    (r"const SnackBar\(\s*content: Text\('databack 文件夹不存在，请先导出数据创建该文件夹'\)", 
     "SnackBar(content: Text(l.backupFolderNotExists)"),
    (r"const SnackBar\(\s*content: Text\('databack 文件夹中没有备份文件'\)", 
     "SnackBar(content: Text(l.noBackupFiles)"),
    (r"title: const Text\('选择备份文件'\),", "title: Text(l.selectBackupFileTitle),"),
    (r"child: const Text\('取消'\),", "child: Text(l.cancel),"),
    
    # 备份恢复相关
    (r"title: const Text\('从自动备份恢复'\),", "title: Text(l.restoreFromAutoBackupTitle),"),
    (r"Text\('备份时间: \$\{_formatDateTime\(backupTime\)\}'\),", "Text('${l.backupTime}: ${_formatDateTime(backupTime)}'),"),
    (r"Text\('任务数量: \$taskCount'\),", "Text('${l.taskCount}: $taskCount'),"),
    (r"Text\('标签数量: \$tagCount'\),", "Text('${l.tagCount}: $tagCount'),"),
    (r"const Text\(\s*'恢复将覆盖当前数据，确定要继续吗？'", 
     "Text(l.restoreConfirmHint"),
    (r"const Text\(\s*'此功能仅支持Web版本'\),", "Text(l.webOnlyFeature),"),
    (r"const Text\(\s*'没有找到自动备份数据'\),", "Text(l.noAutoBackupData),"),
    (r"SnackBar\(content: Text\('已恢复 \$taskCount 个任务和 \$tagCount 个标签'\)", 
     "SnackBar(content: Text(l.restoreSuccessCount('$taskCount', '$tagCount'))"),
    (r"const SnackBar\(content: Text\('恢复失败，请重试'\)", 
     "SnackBar(content: Text(l.restoreFailed)"),
    (r"SnackBar\(content: Text\('读取备份文件夹失败: \$e'\)", 
     "SnackBar(content: Text(l.readBackupFolderError('$e'))"),
    
    # 反馈对话框
    (r"Text\(l\.isZh\n\s+\? '如有问题或建议，请联系：\\nsupport@example.com'\n\s+: 'For questions or suggestions, contact:\\nsupport@example.com'\)", 
     "Text(l.feedbackContact)"),
    
    # 隐私政策
    (r"Text\(\s*l\.isZh\n\s+\? '智能任务助手 隐私政策\\n\\n'\n\s+'1\. 我们重视您的隐私\\n'\n\s+'2\. 所有数据仅存储在本地设备\\n'\n\s+'3\. 我们不会收集或上传您的个人信息\\n'\n\s+'4\. 您可以随时删除所有数据'\n\s+: 'Smart Task Assistant Privacy Policy\\n\\n'\n\s+'1\. We value your privacy\\n'\n\s+'2\. All data is stored locally on your device\\n'\n\s+'3\. We do not collect or upload your personal information\\n'\n\s+'4\. You can delete all data at any time'", 
     "Text(l.privacyPolicyContent)"),
    
    # AI配置对话框
    (r"labelText: 'API Key',", "labelText: l.apiKey,"),
    (r"labelText: l\.isZh \? 'API 地址' : 'API URL',", "labelText: l.apiUrl,"),
    (r"labelText: l\.isZh \? '模型名称' : 'Model Name',", "labelText: l.modelName,"),
    (r"name: 'ollama',\s+'name': l\.isZh \? 'Ollama（本地大模型）' : 'Ollama \(Local LLM\)'", 
     "'name': l.ollama"),
    (r"name: 'custom',\s+'name': l\.isZh \? '自定义 API' : 'Custom API'", 
     "'name': l.customApi"),
    
    # 文件大小单位
    (r"' KB'", "l.kb"),
    
    # 清除数据对话框
    (r"SnackBar\(content: Text\(l\.dataCleared\)", 
     "SnackBar(content: Text(l.dataCleared)"),
]

# 应用替换
count = 0
for pattern, replacement in replacements:
    new_content = re.sub(pattern, replacement, content, flags=re.MULTILINE | re.DOTALL)
    if new_content != content:
        count += 1
        print(f"替换 {count}: {pattern[:50]}...")
    content = new_content

# 写回文件
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'\n总共替换了 {count} 处！')