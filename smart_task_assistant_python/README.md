# 智能任务助手 (Smart Task Assistant)

一个基于 AI 的智能任务管理工具，帮助您高效地创建、管理和跟踪任务。

![版本](https://img.shields.io/badge/版本-v1.0.0-blue)
![Python](https://img.shields.io/badge/Python-3.12+-green)
![PyQt5](https://img.shields.io/badge/PyQt5-5.15+-blue)
![许可](https://img.shields.io/badge/许可-MIT-yellow)

## ✨ 功能特性

### 📋 任务管理
- ✅ 创建、编辑、删除任务
- ✅ 任务状态跟踪（待处理、进行中、已完成、已取消）
- ✅ 优先级管理（高、中、低）
- ✅ 截止时间设置
- ✅ 负责人分配
- ✅ 标签分类

### 🤖 AI 智能识别
- 💬 自然语言输入，自动识别任务信息
- ⏰ 自动提取截止时间
- 👤 自动识别负责人
- 🎯 自动判断优先级
- 📝 自动生成验收标准

### ⏰ 智能提醒
- 🔔 多时间点提醒（30 分钟、1 小时、1 天、3 天等）
- 💬 系统托盘通知
- 🎨 图标闪烁提醒
- 🔄 错过时间后的持续提醒

### 🔄 周期任务
- 📅 每日重复
- 📆 每周重复
- 🗓️ 每月重复
- 🤖 自动创建下一个周期

### 📊 统计分析
- 📈 任务分布统计
- ✅ 完成情况分析
- 🎯 优先级分布
- 📅 时间趋势

### 📋 剪贴板监听
- 📌 自动检测剪贴板内容
- 🧠 智能识别任务信息
- ⚡ 一键快速创建

## 🚀 快速开始

### 环境要求
- Python 3.12+
- Windows / Linux / macOS

### 安装依赖
```bash
pip install -r requirements.txt
```

### 运行程序
```bash
# Windows
run.bat

# Linux / macOS
./run.sh

# 或直接运行
python main.py
```

### 打包应用
```bash
# Windows
打包.bat

# 或手动打包
pyinstaller build.spec
```

## 📖 使用说明

### 创建任务

#### 方法 1: 手动创建
1. 点击"新建任务"按钮
2. 填写任务信息
3. 设置提醒时间
4. 点击"确定"

#### 方法 2: 快速创建
1. 在快速输入框中输入任务描述
2. AI 自动识别任务信息
3. 确认创建

#### 方法 3: 剪贴板创建
1. 复制包含任务信息的文本
2. 系统自动弹出创建对话框
3. 确认创建

### 设置提醒

在创建任务时，可以选择多个提醒时间点：
- ⏰ 提前 30 分钟
- ⏰ 提前 1 小时
- ⏰ 提前 1 天
- ⏰ 提前 3 天

### 周期任务

1. 创建任务时勾选"启用重复"
2. 选择重复频率（每日/每周/每月）
3. 任务完成后自动创建下一个周期

## 🛠️ 技术栈

- **Python 3.12** - 主要编程语言
- **PyQt5** - GUI 框架
- **SQLite** - 本地数据库
- **Requests** - HTTP 请求库
- **Pandas** - 数据处理（导出功能）
- **OpenPyXL** - Excel 文件处理

## 📁 项目结构

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
│   └── widgets/              # 自定义控件
├── tests/                     # 测试文件
├── requirements.txt           # 依赖包
├── README.md                  # 项目说明
├── CHANGELOG.md              # 更新日志
└── VERSIONING.md             # 版本管理指南
```

## 🧪 测试

运行所有测试：
```bash
run_tests.bat
```

或手动运行：
```bash
python -m unittest discover -s tests -v
```

## 📝 更新日志

查看 [CHANGELOG.md](CHANGELOG.md) 了解所有版本更新。

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

## 📄 许可证

MIT License

## 👥 联系方式

- 问题反馈：提交 Issue
- 功能建议：提交 Feature Request

---

**开发时间**: 2026-03-05
**版本**: v1.0.0
