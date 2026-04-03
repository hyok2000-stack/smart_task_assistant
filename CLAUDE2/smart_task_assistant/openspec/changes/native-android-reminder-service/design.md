## Context

Smart Task Assistant 当前的提醒系统完全运行在 Flutter/Dart 层：`ReminderService` 使用 `Timer.periodic(10s)` 轮询，通过 `showDialog()` 弹出提醒。这种方式有以下致命缺陷：

1. App 被切到后台 → Dart Timer 可能被 Android 系统暂停
2. 屏幕锁定 → showDialog 无法弹出
3. App 被系统回收 → 提醒服务直接死亡
4. 低内存设备 → Flutter 引擎可能被优先杀死

现有基础设施：
- `ClipboardMonitorService.kt` 已实现了前台服务模式（FOREGROUND_SERVICE + 通知渠道 + START_STICKY），可以参考
- SQLite 数据库位于 `getDatabasePath("smart_task_assistant.db")`，Kotlin 可直接通过 `SQLiteDatabase` 访问
- `build.gradle.kts` 中 `minSdk = flutter.minSdkVersion`，`targetSdk = flutter.targetSdkVersion`

约束条件：
- 提醒判断逻辑需要在 Kotlin 层独立实现（不依赖 Flutter 引擎）
- DB 为 sqflite 默认使用 WAL 模式，支持并发读写
- 仅覆盖 Android 平台，iOS 不做
- 不新增第三方依赖

## Goals / Non-Goals

**Goals:**
- App 在后台、锁屏、被系统回收后，任务和习惯提醒仍然能可靠触发
- 锁屏状态下全屏弹出提醒页面（类闹钟体验）
- 原生层独立完成 DB 查询 + 时间计算 + 状态管理 + 弹窗 + TTS + 声音 + 振动
- Flutter 前台时仍由 Dart 层处理提醒（体验更好），后台时无缝切换到原生层
- 提醒状态通过 SharedPreferences 管理，两层不冲突

**Non-Goals:**
- 不做 iOS 平台的常驻后台提醒
- 不修改现有数据库表结构
- 不新增第三方依赖（纯 Android SDK API）
- 不实现 `flutter_background_service` 插件（直接用原生 Service）
- 不在 Kotlin 层实现 AI 聊天/任务建议等非提醒功能

## Decisions

### 1. 独立 Service vs 复用 ClipboardMonitorService

**决定**: 创建独立的 `ReminderForegroundService`，不复用剪贴板服务。

**理由**: 两个服务职责完全不同（剪贴板监控 vs 提醒检查），生命周期管理不同（剪贴板可关闭，提醒必须常驻），合并会增加复杂度且互相影响。独立服务也便于后续单独调试和维护。

**替代方案**: 合并到 ClipboardMonitorService — 耦合度高，一个崩溃影响另一个，且通知渠道不同。

### 2. 提醒状态存储：SharedPreferences vs 数据库表

**决定**: 使用 SharedPreferences 存储运行时提醒状态（已发送标记、贪睡时间等）。

**理由**: 提醒状态是临时的、非结构化的键值对（如 `first_sent_{taskId}` → timestamp），SharedPreferences 足够且更轻量。不需要跨 App 重启持久化复杂的关联查询。SQLite 留给 Flutter 层管理结构化数据。

**替代方案**: 新增 `reminder_state` 表 — 需要修改 schema，增加迁移复杂度，且查询模式是简单的 KV 查找，杀鸡用牛刀。

### 3. 前后台分流策略

**决定**: App 前台时 Flutter 层处理（现有 ReminderService），后台时 Kotlin 层接管。通过 MethodChannel 通知原生层切换模式。

**理由**: Flutter 层的 showDialog 体验更好（有动画、上下文、Provider 数据），而原生层 FullScreenActivity 是后台/锁屏场景的必需品。两层互补而非替代。

**替代方案**: 统一由 Kotlin 层处理 — 前台体验降级（原生 Activity 覆盖 Flutter 页面），且无法访问 Provider 的实时数据。

### 4. DB 访问模式

**决定**: Kotlin 层使用 `SQLiteDatabase.openDatabase(path, null, OPEN_READONLY)` 只读打开，每次检查时打开、检查完关闭。

**理由**: sqflite 使用 WAL 模式支持并发读写。Kotlin 只读打开不会与 Flutter 层的写操作冲突。每次打开/关闭避免长时间持有 DB 连接。

### 5. 检查间隔

**决定**: Kotlin 层每 30 秒检查一次（Dart 层为 10 秒）。

**理由**: 后台场景不需要太高的检查频率。30 秒在可接受的提醒延迟范围内（用户感知不明显），同时大幅减少 CPU 唤醒次数，降低电量消耗。

### 6. FullScreenActivity vs 通知栏通知

**决定**: 优先使用 FullScreenIntent（全屏弹窗），降级到高优先级通知。

**理由**: 锁屏场景必须全屏弹出才有效果。Android 14+ 可能无法自动获得全屏权限，此时降级到高优先级通知（带声音、振动、操作按钮），用户点击后打开 App。

**降级策略**:
1. 检查 `canFullScreen()` → 能则全屏弹
2. 不能 → 发 `IMPORTANCE_HIGH` 通知 + 声音 + 振动

## Risks / Trade-offs

**[Android 14+ 全屏通知权限收紧]** → 提供权限引导页面，引导用户到系统设置手动开启。首次启动时检测并提示。降级方案：高优先级通知。

**[双层提醒逻辑不一致]** → Kotlin 层严格复刻 Dart 层的时间计算逻辑，核心判断函数一一对应。测试时对比两层输出确保一致。

**[国产 ROM 后台清理（小米/华为/OPPO）]** → 前台服务 + 常驻通知降低被杀概率。在设置页增加"关闭电池优化"引导。

**[SQLite 并发读写]** → Kotlin 只读打开，sqflite WAL 模式天然支持。极端情况下读取到旧数据，最多导致提醒延迟一个检查周期（30秒）。

**[原生 TTS 与 Flutter TTS 冲突]** → 触发原生提醒前先通过 EventChannel 通知 Flutter 停止 TTS。原生层 TTS 完成后释放。

**[提醒逻辑写两遍]** → 接受这个代价换取可靠性。核心逻辑集中在 `ReminderChecker` 中，函数边界清晰，便于对照 Dart 层代码维护一致性。

**[电量消耗]** → 前台服务 + 30秒轮询会增加耗电。通过 HandlerThread（非主线程）+ 精确的 WakeLock 管理（检查时获取、完成后释放）来控制。
