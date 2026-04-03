## Why

任务提醒在 APP 后台时不工作：用户设置了提醒时间的任务，切到后台或退出后，不会触发振动或语音提醒（但打开 APP 时正常）。习惯提醒（喝水/起身）在后台正常工作，证明原生提醒服务运行正常，问题出在 Kotlin 层对任务的检测逻辑。

## What Changes

- **修复 `parseDueTimeMillis()` 时间解析**：用正则提取替代 `SimpleDateFormat` 严格匹配，解决 Dart `DateTime.toIso8601String()` 输出格式与 Kotlin 解析模式不兼容的问题
- **增强 `queryActiveTasks()` 的诊断日志**：在关键路径加 Log，方便定位未来问题
- **加粗化 `shouldTriggerTask()` 的容错性**：对解析失败的情况输出明确的 Log.w 而非静默返回 false

## Capabilities

### New Capabilities

（无新增能力）

### Modified Capabilities

- `native-reminder-service`：修复任务提醒在后台不触发的问题，增强时间解析和诊断日志

## Impact

- **Kotlin 层**：`ReminderChecker.kt` — `parseDueTimeMillis()` 重写、`checkAll()` 加日志
- **Flutter 层**：无改动
- **数据库**：无改动
- **兼容性**：完全向后兼容，只修改解析逻辑和日志
