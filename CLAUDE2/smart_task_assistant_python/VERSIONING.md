# 版本管理指南

## Git 配置

### 1. 初始化仓库（如果尚未初始化）
```bash
cd D:\OneDrive\WORK\personal\GIT\smart_task_assistant_python
git init
```

### 2. 配置用户信息
```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

### 3. 添加文件
```bash
git add .
```

### 4. 提交更改
```bash
git commit -m "描述更改内容"
```

## 版本历史

### v1.0.0 (2026-03-05) - 初始版本
**功能特性:**
- ✅ 任务管理（创建、编辑、删除、完成）
- ✅ 智能识别（本地 AI 识别任务信息）
- ✅ 提前告警（支持多时间点提醒：30 分钟、1 小时、1 天、3 天等）
- ✅ 周期任务（自动创建下一个周期：每日、每周、每月）
- ✅ 数据备份与导出（JSON、Excel）
- ✅ 系统托盘集成（托盘菜单、通知提醒）
- ✅ 剪贴板监听（自动识别任务）
- ✅ 统计界面（任务分布、完成情况）
- ✅ 智能建议（逾期提醒、优先级筛选）

**技术栈:**
- Python 3.12
- PyQt5 (GUI)
- SQLite (数据库)
- 本地 AI 模型集成

**核心文件结构:**
```
smart_task_assistant_python/
├── main.py                    # 程序入口
├── core/                      # 核心模块
│   ├── ai_service.py         # AI 服务
│   ├── database.py           # 数据库管理
│   ├── config.py             # 配置管理
│   ├── clipboard.py          # 剪贴板服务
│   ├── reminder_service.py   # 提醒服务
│   └── recognition.py        # 任务识别
├── ui/                        # 用户界面
│   ├── main_window.py        # 主窗口
│   ├── task_create_dialog.py # 创建任务对话框
│   ├── task_detail_dialog.py # 任务详情对话框
│   ├── settings_dialog.py    # 设置对话框
│   ├── chat_dialog.py        # 聊天对话框
│   ├── about_dialog.py       # 关于对话框
│   └── widgets/              # 自定义控件
│       ├── task_card.py      # 任务卡片
│       └── stats_card.py     # 统计卡片
├── tests/                     # 测试文件
│   ├── test_base.py
│   ├── test_core.py
│   └── test_performance.py
├── requirements.txt           # 依赖包
└── .gitignore                # Git 忽略文件
```

## 推荐的版本标签

### 功能里程碑
- **v1.0.0** - 初始发布版本（当前版本）
- **v1.1.0** - 计划：添加云同步功能
- **v1.2.0** - 计划：添加移动端支持
- **v2.0.0** - 计划：重构为 Web 应用

### 创建版本标签
```bash
# 创建当前版本标签
git tag -a v1.0.0 -m "Initial release"

# 推送标签到远程仓库
git push origin --tags
```

## 分支管理策略

### 分支命名
- `main` - 主分支，稳定版本
- `develop` - 开发分支
- `feature/xxx` - 功能分支
- `bugfix/xxx` - 修复分支
- `hotfix/xxx` - 紧急修复分支

### 创建开发分支
```bash
git checkout -b develop
git checkout -b feature/reminder-enhancement
git checkout -b bugfix/task-delete-issue
```

## 提交规范

### Commit Message 格式
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type 类型
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具/配置

### 示例
```bash
git commit -m "feat(reminder): 添加多时间点提醒功能

- 支持设置提前 30 分钟、1 小时、1 天、3 天提醒
- 优化提醒逻辑，支持错过时间后的持续提醒
- 每 5 分钟重复提醒一次

Closes #123"
```

## 备份策略

### 本地备份
```bash
# 创建备份目录
mkdir backup_$(date +%Y%m%d)

# 备份重要文件
cp -r core/ backup_$(date +%Y%m%d)/
cp -r ui/ backup_$(date +%Y%m%d)/
cp main.py backup_$(date +%Y%m%d)/
```

### 远程仓库
```bash
# 添加远程仓库
git remote add origin https://github.com/yourusername/smart_task_assistant.git

# 推送代码
git push -u origin main
```

## 发布流程

### 1. 版本号更新
更新 `main.py` 或单独的版本文件中的版本号

### 2. 更新 CHANGELOG.md
记录所有更改

### 3. 创建发布版本
```bash
# 打包应用
python build.bat

# 创建发布标签
git tag -a v1.0.0 -m "Release v1.0.0"

# 推送到远程
git push origin --tags
```

### 4. 发布说明
- 功能列表
- 修复的问题
- 已知问题
- 升级说明

## 常见问题

### Q: 如何回滚到之前的版本？
```bash
# 查看历史版本
git log --oneline

# 回滚到指定版本
git checkout <commit-hash>

# 或创建回滚分支
git checkout -b rollback-branch <commit-hash>
```

### Q: 如何合并两个分支？
```bash
# 切换到目标分支
git checkout main

# 合并功能分支
git merge feature/reminder-enhancement

# 解决冲突后提交
git commit -m "Merge feature/reminder-enhancement"
```

### Q: 如何撤销未提交的更改？
```bash
# 撤销工作区更改
git checkout .

# 或撤销暂存区更改
git reset HEAD
```

## 维护建议

1. **定期提交**: 每天至少提交一次，保持代码历史清晰
2. **小步提交**: 每个功能点单独提交，便于回滚
3. **代码审查**: 重要功能合并前进行代码审查
4. **测试覆盖**: 提交前运行所有测试
5. **文档更新**: 功能变更后及时更新文档

---

**最后更新**: 2026-03-05
**版本**: v1.0.0
