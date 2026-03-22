# 🎯 智能任务助手 (Smart Task Assistant)

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.2.0+-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.2.0+-0175C2?logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-4285F4)
![License](https://img.shields.io/badge/License-MIT-green)
![Version](https://img.shields.io/badge/Version-1.3.14-blue)

**基于AI的智能任务管理工具 | Smart Task Management with AI**

[功能特性](#-功能特性) • [快速开始](#-快速开始) • [截图展示](#-截图展示) • [技术栈](#-技术栈) • [贡献指南](#-贡献指南)

</div>

---

## 📖 项目简介

智能任务助手是一款基于Flutter开发的跨平台任务管理应用，通过自然语言处理和AI技术，让任务管理变得更加智能和高效。

### ✨ 核心亮点

- 🤖 **AI智能解析** - 支持自然语言输入，自动识别时间、优先级、标签
- 💬 **AI助手对话** - 内置AI聊天功能，提供任务建议和使用帮助
- ⏰ **智能提醒** - 多种提醒方式，支持周期任务和稍后提醒
- 📊 **数据分析** - 可视化统计，任务进度一目了然
- 🌍 **跨平台支持** - Android、iOS、Web、Desktop全平台运行
- 📴 **离线优先** - 本地数据库，无需联网也能使用

### 🎯 适用场景

- 📱 个人日常任务管理
- 💼 工作项目跟踪
- 📚 学习计划安排
- 🏠 家庭事务管理
- 🚀 提高生产力

---

## 🚀 功能特性

### 🤖 AI智能功能

#### 自然语言任务解析
```
输入示例：
"明天下午3点开会 #工作 @张三 紧急"

自动识别：
✅ 时间：明天下午3点
✅ 标签：工作
✅ 负责人：张三
✅ 优先级：紧急
✅ 标题：开会
```

#### AI智能助手
- 💬 多轮对话交互
- 📊 任务优先级分析
- 💡 效率提升建议
- 🔍 任务智能推荐
- ❓ 使用帮助解答

#### 支持的AI模型
- 🏠 本地规则引擎（默认，无需配置）
- 🤖 Ollama
- 🌐 OpenAI
- 🇨🇳 通义千问
- 🧠 智谱AI
- 🚀 Kimi
- ⚙️ 自定义API

### ⏰ 任务管理

#### 基础功能
- ➕ 快速添加任务
- ✏️ 任务编辑与删除
- ✅ 任务状态管理（待处理/进行中/已完成/已取消）
- 🔖 优先级设置（低/中/高）
- 🏷️ 标签分类管理
- 📎 附件支持

#### 高级功能
- 🔄 周期任务（每日/每周/每月）
- ⏱️ 提醒设置（自定义时间）
- 🔔 多种提醒方式（声音/振动/通知）
- 📅 截止时间管理
- 👤 负责人分配
- 📝 任务详情描述

### 🔔 智能提醒系统

#### 提醒方式
- 🔊 声音提醒（支持自定义音频）
- 📳 振动提醒（可调节强度）
- 📱 系统通知
- 💬 弹窗提醒

#### 提醒交互
- ⏳ 稍后提醒（自定义时间）
- 🕐 修改提醒时间
- ❌ 关闭提醒
- ✅ 标记完成
- 🔄 持续提醒机制

### 📊 数据统计

#### 统计维度
- ✅ 完成进度
- 📋 任务分布（状态/优先级）
- 📅 时间趋势
- 🏷️ 标签统计

#### 可视化展示
- 📊 环形进度图
- 📈 柱状图
- 🥧 饼图
- 📉 折线图

### 🌦️ 天气集成

- 📍 基于当前位置获取天气
- 🌡️ 实时温度显示
- ☁️ 天气状况展示
- 🔄 手动刷新功能

### 📋 剪贴板监控

- 🔍 自动监控剪贴板
- ⚡ 快速添加任务
- 🔘 可开关控制

### 💾 数据管理

- 💾 本地SQLite数据库
- 📤 数据导出（JSON）
- 📥 数据导入
- 🗑️ 数据清除
- 🔒 数据安全

---

## 📸 截影展示

<!-- TODO: 添加实际截图 -->

### 主界面
- 任务列表展示
- 进度统计卡片
- 天气信息
- AI建议推荐

### AI聊天
- 智能对话界面
- 任务优先级分析
- 快捷操作按钮

### 添加任务
- 自然语言输入
- 快速编辑功能
- 标签选择器

### 统计分析
- 数据可视化
- 趋势图表
- 详细统计

---

## 🛠️ 技术栈

### 核心框架

| 技术 | 版本 | 用途 |
|------|------|------|
| Flutter | 3.2.0+ | UI框架 |
| Dart | 3.2.0+ | 编程语言 |
| Provider | 6.1.1 | 状态管理 |

### 数据存储

| 技术 | 版本 | 用途 |
|------|------|------|
| sqflite | 2.3.0 | SQLite数据库 |
| shared_preferences | 2.2.2 | 键值存储 |
| path_provider | 2.1.1 | 文件路径 |

### UI组件

| 技术 | 版本 | 用途 |
|------|------|------|
| flutter_slidable | 3.0.1 | 滑动操作 |
| shimmer | 3.0.0 | 加载动画 |
| fl_chart | 0.66.0 | 图表可视化 |

### 网络与通信

| 技术 | 版本 | 用途 |
|------|------|------|
| dio | 5.4.0 | HTTP客户端 |
| http | 1.2.0 | 网络请求 |

### 功能增强

| 技术 | 版本 | 用途 |
|------|------|------|
| flutter_local_notifications | 17.0.0 | 本地通知 |
| flutter_background_service | 5.0.10 | 后台服务 |
| audioplayers | 6.0.0 | 音频播放 |
| vibration | 2.0.0 | 振动反馈 |
| geolocator | 12.0.0 | 位置服务 |
| geocoding | 3.0.0 | 地理编码 |

### 工具库

| 技术 | 版本 | 用途 |
|------|------|------|
| intl | 0.20.2 | 国际化 |
| uuid | 4.2.1 | 唯一标识 |
| permission_handler | 11.1.0 | 权限管理 |

---

## 🏗️ 项目结构

```
smart_task_assistant/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── database/                 # 数据库层
│   │   ├── database_helper.dart  # 数据库帮助类
│   │   └── storage_service.dart  # 存储服务抽象
│   ├── models/                   # 数据模型
│   │   ├── task.dart             # 任务模型
│   │   ├── tag.dart              # 标签模型
│   │   └── task_suggestion.dart  # 任务建议模型
│   ├── providers/                # 状态管理
│   │   ├── task_provider.dart    # 任务状态
│   │   └── settings_provider.dart # 设置状态
│   ├── services/                 # 业务服务
│   │   ├── ai_service.dart       # AI服务
│   │   ├── reminder_service.dart # 提醒服务
│   │   ├── clipboard_monitor_service.dart # 剪贴板监控
│   │   └── weather_service.dart  # 天气服务
│   ├── screens/                  # 页面
│   │   ├── home_screen.dart      # 主页
│   │   ├── add_task_screen.dart  # 添加任务页
│   │   ├── settings_screen.dart  # 设置页
│   │   └── stats_screen.dart     # 统计页
│   ├── widgets/                  # 组件
│   │   ├── task_card.dart        # 任务卡片
│   │   ├── ai_chat_dialog.dart   # AI聊天对话框
│   │   └── quick_add_modal.dart  # 快速添加模态框
│   ├── theme/                    # 主题
│   │   └── app_theme.dart        # 应用主题
│   └── utils/                    # 工具类
│       ├── app_logger.dart       # 日志工具
│       └── app_localizations.dart # 国际化
├── android/                      # Android平台代码
├── ios/                          # iOS平台代码
├── web/                          # Web平台代码
├── windows/                      # Windows平台代码
├── linux/                        # Linux平台代码
├── macos/                        # macOS平台代码
├── assets/                       # 资源文件
│   └── sounds/                   # 音频文件
└── test/                         # 测试代码
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- Android Studio / VS Code
- 对应平台的开发工具（Android Studio for Android, Xcode for iOS）

### 安装步骤

#### 1. 克隆项目

```bash
git clone https://github.com/yourusername/smart_task_assistant.git
cd smart_task_assistant
```

#### 2. 安装依赖

```bash
flutter pub get
```

#### 3. 运行项目

```bash
# Android
flutter run

# iOS
flutter run -d ios

# Web
flutter run -d chrome

# Desktop (Windows)
flutter run -d windows

# Desktop (macOS)
flutter run -d macos

# Desktop (Linux)
flutter run -d linux
```

#### 4. 构建发布版本

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

---

## 🎯 核心功能说明

### AI配置

#### 本地规则引擎（默认）
无需任何配置，开箱即用。

#### 外部AI模型

1. 打开设置 → AI配置
2. 选择AI提供商
3. 填写API密钥
4. 点击测试连接
5. 保存配置

**支持的AI提供商：**
- OpenAI (https://platform.openai.com/api-keys)
- 通义千问 (https://dashscope.aliyun.com/api-key)
- 智谱AI (https://open.bigmodel.cn/usercenter/apikeys)
- Kimi (https://platform.moonshot.cn/console/api-keys)
- Ollama (本地部署)
- 自定义API

### 自然语言解析示例

#### 时间识别
```
今天 -> 今天00:00
明天 -> 明天00:00
后天 -> 后天00:00
周一 -> 下周一00:00
下午3点 -> 今天15:00
明天上午10点 -> 明天10:00
3天后 -> 3天后00:00
2小时后 -> 2小时后
```

#### 优先级识别
```
紧急 -> 高优先级
重要 -> 中优先级
不急 -> 低优先级
```

#### 标签提取
```
#工作 -> 标签：工作
#学习 -> 标签：学习
```

#### 完整示例
```
输入：
"明天下午3点开会 #工作 @张三 紧急"

解析结果：
标题：开会
时间：明天15:00
标签：工作
负责人：张三
优先级：高
```

### 提醒设置

1. 创建/编辑任务
2. 设置截止时间
3. 选择提醒时间（如提前10分钟）
4. 保存任务

系统将在指定时间触发提醒，提供以下选项：
- ⏳ 稍后提醒
- 🕐 修改时间
- ❌ 关闭提醒
- ✅ 标记完成

### 周期任务

1. 创建任务
2. 启用"周期任务"
3. 选择周期规则（每日/每周/每月）
4. 保存任务

当任务完成后，系统会自动创建下一个周期的任务。

---

## 📝 开发计划

### ✅ 已实现功能

- [x] 基础任务管理（CRUD）
- [x] 自然语言任务解析
- [x] AI智能助手
- [x] 智能提醒系统
- [x] 周期任务
- [x] 标签管理
- [x] 任务统计与分析
- [x] 数据可视化
- [x] 天气集成
- [x] 剪贴板监控
- [x] 数据导入导出
- [x] 跨平台支持

### 🚧 计划中功能

- [ ] 任务依赖关系
- [ ] 任务模板
- [ ] 团队协作
- [ ] 富文本编辑
- [ ] 云端同步
- [ ] 日历视图
- [ ] 语音输入
- [ ] OCR识别
- [ ] 任务分享
- [ ] 插件系统

---

## 🤝 贡献指南

欢迎贡献代码、报告问题或提出建议！

### 如何贡献

1. Fork本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交Pull Request

### 代码规范

- 遵循Dart代码规范
- 使用 `flutter analyze` 检查代码
- 添加必要的注释
- 编写单元测试（如适用）

### 报告问题

提交Issue时，请包含以下信息：
- 问题描述
- 复现步骤
- 预期行为
- 实际行为
- 环境信息（Flutter版本、平台等）
- 截图或日志（如适用）

---

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源协议。

---

## 👨‍💻 作者

**智能任务助手开发团队**

- 项目主页：[GitHub](https://github.com/yourusername/smart_task_assistant)
- 问题反馈：[Issues](https://github.com/yourusername/smart_task_assistant/issues)

---

## 🙏 致谢

感谢以下开源项目和贡献者：

- [Flutter](https://flutter.dev/) - 跨平台UI框架
- [Provider](https://pub.dev/packages/provider) - 状态管理
- [sqflite](https://pub.dev/packages/sqflite) - SQLite数据库
- [fl_chart](https://pub.dev/packages/fl_chart) - 图表可视化

---

## 📞 联系方式

如有问题或建议，欢迎通过以下方式联系：

- 提交 [GitHub Issue](https://github.com/yourusername/smart_task_assistant/issues)
- 发送邮件：your-email@example.com

---

<div align="center">

**如果这个项目对您有帮助，请给个⭐️ Star支持一下！**

Made with ❤️ by Smart Task Assistant Team

</div>