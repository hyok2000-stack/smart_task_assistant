# 智能任务助手 - 开发路线图

> 2026-10 更新：早期路线图严重过时（大量"待开发"功能实际已完成），已重写。
> 当前版本：2.2.16+190

## 已完成功能 ✅

### 任务管理
- 手动/快速创建任务（标题、内容、截止时间、优先级、标签、负责人、重复规则）
- 任务编辑、删除、批量归档/恢复、子任务（parent_id）、评论、操作历史
- 全文搜索 + 多维筛选

### AI 能力
- 自然语言解析（本地规则引擎 + 外部 AI 双通道）：时间/相对时间/优先级/标签/负责人
- OCR 拍照识别（ML Kit 中文离线）→ 自动解析任务字段
- AI 智能建议、AI 对话（多 provider：OpenAI/通义/智谱/Kimi/Ollama）

### 提醒系统（前后台双通道）
- 前台：Flutter 轮询 + 弹窗 + TTS 播报
- 后台/熄屏/杀进程：原生前台服务 + 30s 闹钟链，铃声多级兜底 + 音量流自适应
  + TTS 文件合成播报（规避华为 ROM 冻结 TTS 实时输出）
- 语音自定义（TTS 音色/语速/自定义音频）、免打扰时段、推荐提醒时长
- 稍后提醒（10分钟/1小时）、延期到明日（真实更新截止时间）、不再提醒

### 其他
- 习惯打卡（喝水/拉伸/上下班打卡，间隔+固定时间两种触发）
- 统计分析（分布图表、完成率、时间趋势）
- 天气（高德 API）、剪贴板监听建任务、多主题、双语基建（未全面接入）
- 后端同步（Go task_server，任务协作/评论/指派）

## 已知技术债 🚧

- [ ] **添加任务双入口去重**：add_task_screen 与 quick_add_modal 平行实现 OCR/AI 解析/选择器，抽 TaskParseController（收益最大）
- [ ] **提醒查询部分索引**：reminder_dismissed/archived_at 无索引，30s 轮询全表扫描（升 v16）
- [ ] use_build_context_synchronously 22 处（异步后使用 context）
- [ ] SettingsProvider 拆分（754 行，主题/通知/TTS/双套 AI 配置混杂）
- [ ] task_history_service 无条数上限（SharedPreferences 全量重写）
- [ ] reminder_service 反向依赖 providers/widgets（依赖倒置，无法独立测试）
- [ ] i18n 决策：AppLocalizations 基建在但 UI 全部硬编码中文
- [ ] 默认后端地址 http://10.0.2.2:4100 真机不可用（需 https 或 network_security_config）
