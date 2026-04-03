## Context

APP 使用 Flutter 层（Dart Timer 10s）做前台提醒，Kotlin 层（AlarmManager 30s）做后台提醒。习惯后台提醒正常，任务后台提醒完全失效。两者共享同一个 `checkAll()` → 同一个 DB 连接。

根因定位：`ReminderChecker.parseDueTimeMillis()` 使用 `SimpleDateFormat` 严格匹配 4 种模式，但 Dart `DateTime.toIso8601String()` 的实际输出可能在某些设备/ROM 上与预期格式不匹配（如小数位数、时区后缀等）。解析返回 `null` → `shouldTriggerTask()` 首行 `return false`。

习惯不受影响因为 `parseTimeToTodayMillis()` 只解析 `"HH:mm"` 格式，极其简单。

## Goals / Non-Goals

**Goals:**
- 修复任务提醒在 APP 后台时不工作的问题
- 增强 Kotlin 层的诊断日志，方便未来排查

**Non-Goals:**
- 不修改 Flutter 层代码
- 不修改数据库 schema
- 不新增第三方依赖
- 不修改习惯提醒逻辑（已正常工作）

## Decisions

### 1. 用正则提取替代 SimpleDateFormat 严格匹配

**决定**: 使用正则 `"""(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})"""` 提取年月日时分秒，再用 `Calendar` 构造时间戳。

**理由**: 
- 正则只关心数字结构，忽略小数位数、时区后缀等变化
- 不依赖 `SimpleDateFormat` 的 locale 和 leniency 行为
- 习惯的 `parseTimeToTodayMillis()` 已证明直接构造 Calendar 是可靠的

**替代方案**: 保留 `SimpleDateFormat` 并增加更多模式 → 脆弱，Dart 输出格式变化仍可能不匹配

### 2. 保留 SimpleDateFormat 作为降级方案

**决定**: 正则匹配优先，失败后尝试原有 `SimpleDateFormat` 链。

**理由**: 防御性编程，两种方式互补。

### 3. 在 checkAll() 的任务路径添加诊断日志

**决定**: 在任务查询、遍历、触发判断的每个关键节点加 `Log.d`。

**理由**: 当前 Kotlin 层几乎没有日志，问题难以定位。加日志是一次性工作但长期受益。

## Risks / Trade-offs

**[正则提取忽略时区信息]** → Dart 本地时间不带时区后缀，Kotlin 用 `Calendar.getInstance()` 默认本地时区，两者一致。如果是 UTC 时间会有偏差，但 Dart 端存的都是本地时间，风险极低。 → 无需额外处理

**[日志量增加]** → 仅在 `checkAll()` 任务路径加日志，每 30s 输出几行，不影响性能 → 可接受
