## 1. 修复时间解析

- [x] 1.1 在 `ReminderChecker.parseDueTimeMillis()` 中添加正则提取方式：用 `"""(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})"""` 提取年月日时分秒，用 `Calendar` 构造时间戳，作为首选解析方式
- [x] 1.2 保留原有 `SimpleDateFormat` 链作为 fallback，放在正则提取之后
- [x] 1.3 对解析失败的情况（正则不匹配 + fallback 也失败）输出 `Log.w` 日志，包含原始 `due_time` 字符串值

## 2. 添加诊断日志

- [x] 2.1 在 `checkAll()` 的任务查询后加 `Log.d`，输出查询到的活跃任务数量
- [x] 2.2 在 `shouldTriggerTask()` 方法入口处加 `Log.d`，输出 dueTime 字符串和解析结果
- [x] 2.3 在 `shouldTriggerTask()` 每个判断分支加 `Log.d`，输出具体原因

## 3. 验证

- [x] 3.1 编译运行 APP，创建一个 1 分钟后提醒的任务
- [x] 3.2 切到后台，等待提醒时间到达，确认 logcat 中能看到任务检测日志和触发结果
- [x] 3.3 确认后台触发时能听到声音/振动/语音提醒
