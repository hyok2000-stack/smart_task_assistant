## Why

当前的提醒系统完全依赖 Dart 层 Timer + showDialog，App 切后台、被系统回收或屏幕锁定后，Timer 被暂停、弹窗无法弹出，提醒完全失效。作为一个任务管理工具，提醒的可靠性是核心价值——用户设置了任务截止时间和习惯提醒，却因为 App 在后台而错过提醒，这是不可接受的。

## What Changes

- 新增 Android 原生前台服务 `ReminderForegroundService`，独立于 Flutter 引擎运行，系统杀死 App 后自动重启（START_STICKY）
- 新增 `ReminderChecker`，在 Kotlin 层直接读取 SQLite 数据库，独立完成所有提醒判断逻辑（任务 + 习惯），不依赖 Flutter
- 新增 `FullScreenReminderActivity`，锁屏状态下也能全屏弹出提醒页面（showWhenLocked + turnScreenOn），用户无需解锁即可操作
- 新增原生 TTS 播放能力 `ReminderTtsHelper`，使用 Android 原生 TextToSpeech 引擎 + MediaPlayer 播放自定义语音，参数映射与 Flutter 层完全一致
- 新增原生声音/振动播放 `ReminderAudioHelper`，使用 MediaPlayer (USAGE_ALARM) + Vibrator，静音模式也能播放
- 新增 Flutter ↔ Kotlin 通信层（MethodChannel + EventChannel），App 前台时 Flutter 层处理提醒，后台时 Kotlin 层接管，两层不冲突
- 修改 `main.dart`，App 生命周期变化时通知原生层切换前后台模式
- 修改 `reminder_service.dart`，后台时跳过 Dart 层检查，避免双层弹窗冲突
- 新增 Android 14+ 全屏通知权限引导流程

## Capabilities

### New Capabilities
- `native-reminder-service`: Android 原生前台服务，包含提醒检查循环、DB读取、状态管理（SharedPreferences）
- `full-screen-reminder-ui`: 锁屏全屏弹窗 Activity，任务提醒和习惯提醒的 UI 展示与用户操作处理
- `native-tts-audio`: 原生 TTS 语音合成 + 自定义音频播放 + 提醒铃声 + 振动
- `flutter-kotlin-bridge`: Flutter 与 Kotlin 之间的双向通信层，前后台切换、数据变更通知、事件回调

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **Android 原生层**: 新增 5 个 Kotlin 文件（Service, Checker, Activity, AudioHelper, TtsHelper）
- **AndroidManifest.xml**: 新增 USE_FULL_SCREEN_INTENT 权限、注册 Service 和 Activity
- **Flutter 层**: 修改 `main.dart`（生命周期通知）、`reminder_service.dart`（前台/后台分流）
- **数据库**: Kotlin 层只读访问现有 SQLite，通过 SharedPreferences 管理提醒状态，不修改表结构
- **依赖**: 无新增第三方依赖，全部使用 Android SDK 原生 API
- **兼容性**: 目标 Android API 24+ (Android 7.0)，Android 14+ 需引导用户手动开启全屏通知权限
- **平台范围**: 仅 Android，iOS 因后台限制不做此方案
