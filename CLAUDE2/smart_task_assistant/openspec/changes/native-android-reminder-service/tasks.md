## 1. Android Manifest & Permissions

- [x] 1.1 Add `USE_FULL_SCREEN_INTENT` permission to `AndroidManifest.xml`
- [x] 1.2 Register `ReminderForegroundService` in manifest with `foregroundServiceType="specialUse"`
- [x] 1.3 Register `FullScreenReminderActivity` in manifest with attributes: `showWhenLocked=true`, `turnScreenOn=true`, `launchMode=singleInstance`, `excludeFromRecents=true`
- [x] 1.4 Create `res/values/styles.xml` with `ReminderTheme` (full-screen, no action bar, transparent status/nav bars)

## 2. ReminderChecker — DB Query & Logic

- [x] 2.1 Create `ReminderChecker.kt` with SQLiteDatabase read-only access to `smart_task_assistant.db`
- [x] 2.2 Implement `queryActiveTasks()`: SQL query filtering `status IN (0,1)`, `reminder_dismissed=0`, `reminder_minutes NOT NULL`, `due_time NOT NULL`, parsing result into data class `TaskRow`
- [x] 2.3 Implement `queryEnabledHabits()`: SQL query `SELECT * FROM habits WHERE is_enabled = 1`, parsing into `HabitRow` data class
- [x] 2.4 Implement `queryWorkTimeRange()`: query clock_in/clock_out habits for `reference_time`, defaulting to (9, 18)
- [x] 2.5 Implement task reminder logic: `shouldTriggerTask()` with snooze check, first-reminder check (`reminderTime = due_time - reminder_minutes`), continual reminder check (30s interval), and deadline+1h cutoff
- [x] 2.6 Implement habit fixed-time logic: `shouldTriggerFixedHabit()` with clock-habit special handling (reference_time + advance_minutes), ±1 minute window, today-already-triggered guard (SP `habit_fixed_{id}_{date}`)
- [x] 2.7 Implement habit interval logic: `shouldTriggerIntervalHabit()` with work-time range, trigger sequence generation (`startTime + N*interval`), ±1 minute match, and `habit_last_{id}` SP guard
- [x] 2.8 Implement weekday/daily schedule check
- [x] 2.9 Implement SharedPreferences state management: `markFirstSent()`, `markLastRemind()`, `setSnooze()`, `clearTaskState()`, `markHabitTriggered()`, `isHabitTriggeredInWindow()`, `cleanupStaleState()`
- [x] 2.10 Implement `checkAll()` main entry: query DB → iterate tasks → iterate habits → return `List<ReminderItem>`
- [ ] 2.11 Write unit tests for `ReminderChecker` covering all time calculation edge cases (mock time, mock SP)

## 3. ReminderForegroundService

- [x] 3.1 Create `ReminderForegroundService.kt` extending `Service`, with `START_STICKY` return
- [x] 3.2 Implement `onCreate()`: create notification channel (IMPORTANCE_LOW for service notification), start foreground with persistent notification
- [x] 3.3 Implement `onStartCommand()`: initialize HandlerThread, post first check, schedule recurring checks every 30 seconds
- [x] 3.4 Implement `onHandleCheck()`: acquire partial WakeLock → call `checker.checkAll()` → for each ReminderItem trigger sound/vibration/TTS/activity → release WakeLock
- [x] 3.5 Implement `onDestroy()`: stop HandlerThread, release all WakeLocks, cancel pending callbacks
- [x] 3.6 Implement `setAppForeground(isForeground: Boolean)` to toggle FullScreenActivity suppression
- [x] 3.7 Implement `refreshData(type: String, id: String?)` to clear SP caches for updated items
- [x] 3.8 Implement `clearState(id: String)` to remove all SP entries for a specific task/habit

## 4. ReminderAudioHelper — Sound & Vibration

- [x] 4.1 Create `ReminderAudioHelper.kt` with `playReminderSound(context)`: try asset sound → fallback to system default notification sound, using `MediaPlayer` with `USAGE_ALARM` audio attributes
- [x] 4.2 Implement asset sound extraction: copy `assets/sounds/notification.mp3` to `filesDir/sounds/` on first run (if not already copied)
- [x] 4.3 Implement `playVibration(context)`: `VibrationEffect.createWaveform(longArrayOf(0, 300, 100, 300, 100, 300), -1)`
- [x] 4.4 Implement `playSequence()`: orchestrate sound + vibration simultaneously, then delay 1s before returning (caller then triggers TTS)

## 5. ReminderTtsHelper — Native TTS

- [x] 5.1 Create `ReminderTtsHelper.kt` with `TextToSpeech` initialization on HandlerThread, `CountDownLatch` for init sync
- [x] 5.2 Implement `speak(text, voiceType, voiceStyle, speed, customVoicePath)`: if custom path exists → play via MediaPlayer; else → set pitch/speechRate → tts.speak()
- [x] 5.3 Implement pitch calculation: male=0.7, female=1.3, neutral=1.0 + gentle=-0.1, lively=+0.1 (matching Flutter `_getPitch()`)
- [x] 5.4 Implement speech rate mapping: slow=0.8, normal=1.0, fast=1.4 (matching Flutter perceived speed)
- [x] 5.5 Implement `stop()` and `release()` cleanup methods

## 6. FullScreenReminderActivity

- [x] 6.1 Create `FullScreenReminderActivity.kt` with full-screen theme, `setShowWhenLocked(true)`, `setTurnScreenOn(true)`, and `FLAG_SHOW_WHEN_LOCKED` for backward compat
- [x] 6.2 Implement WakeLock management: acquire `SCREEN_BRIGHT_WAKE_LOCK + ACQUIRE_CAUSES_WAKEUP` in `onCreate()`, release in `onDestroy()`
- [x] 6.3 Implement task reminder UI layout: gradient background, notification icon, priority badge (color-coded), task title, due time, assignee, action buttons (10min/30min/1hr snooze + dismiss)
- [x] 6.4 Implement habit reminder UI layout: icon with colored background, title, reminder text, progress bar (for non-clock habits), action buttons (clock: "知道了"; activity: "不再提醒"/"已完成" + snooze options)
- [x] 6.5 Implement button handlers: snooze → write SP `snooze_{id}` + send EventChannel; dismiss → write DB `reminder_dismissed=1` + send EventChannel; complete → write DB `habit_logs` + send EventChannel
- [x] 6.6 Implement back-press / swipe-dismiss handler: for tasks, set `snooze_{id} = now + 30s`; for habits, just finish
- [x] 6.7 Implement notification fallback: detect `canUseFullScreenIntent()` permission, if denied → post `IMPORTANCE_HIGH` notification with full-screen pending intent and action buttons via `NotificationCompat`

## 7. Flutter ↔ Kotlin Bridge — MainActivity

- [x] 7.1 Add MethodChannel `"com.smarttask.smart_task_assistant/reminder"` handler in `MainActivity.configureFlutterEngine()`
- [x] 7.2 Implement method handlers: `startService`, `stopService`, `notifyAppForeground`, `notifyAppBackground`, `notifyDataChanged`, `clearReminderState`, `requestFullScreenPermission`, `isServiceRunning`
- [x] 7.3 Add EventChannel `"com.smarttask.smart_task_assistant/reminder_events"` with broadcast stream controller
- [x] 7.4 Implement event buffer (max 10 entries) for events fired when Flutter is not listening, with replay on re-attach
- [x] 7.5 Expose event-sending method to `ReminderForegroundService` and `FullScreenReminderActivity` (via companion/broadcast)

## 8. Flutter Layer Integration

- [x] 8.1 Add MethodChannel and EventChannel constants and initialization to `_MyAppState` in `main.dart`
- [x] 8.2 Implement `_startNativeReminderService()` called after `_loadData()` completes: invoke `startService()` + `notifyAppForeground()` + begin EventChannel listening
- [x] 8.3 Implement `didChangeAppLifecycleState` updates: `resumed` → `notifyAppForeground()`, `paused` → `notifyAppBackground()`
- [x] 8.4 Implement `_handleReminderEvent(Map event)` to process native events: completed/snoozed/dismissed/shown → delegate to `TaskProvider`/`HabitProvider`
- [x] 8.5 Modify `ReminderService` in `reminder_service.dart`: add `isAppForeground` flag, skip `_checkReminders()` when app is background, add `markShown(id)` and `setSnooze(id, minutes)` methods
- [x] 8.6 Add `notifyDataChanged()` calls after task/habit CRUD operations in providers
- [x] 8.7 Implement `dispose()` cleanup: cancel EventChannel subscription, invoke `stopService()`

## 9. Permission & Settings UI

- [x] 9.1 Add permission check helper: detect Android 14+ and query `NotificationManager.canUseFullScreenIntent()`
- [x] 9.2 Add permission request flow in settings screen: if permission not granted, show explanation + button that opens system settings via `Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`
- [x] 9.3 Add service status indicator in settings: show whether `ReminderForegroundService` is running, with enable/disable toggle

## 10. Testing & Validation

- [ ] 10.1 Write unit tests for `ReminderChecker` time calculations (mock System.currentTimeMillis, test all branches)
- [ ] 10.2 Write integration test: create test task in DB → verify Kotlin layer detects it → verify FullScreenActivity launches
- [ ] 10.3 Test lock-screen behavior: lock device with active reminder → verify screen turns on and full-screen activity appears
- [ ] 10.4 Test background kill recovery: force-stop app → verify service restarts and reminders resume
- [ ] 10.5 Test Flutter/Kotlin state sync: complete task in FullScreenActivity → verify Flutter UI updates on next resume
- [ ] 10.6 Test Android 14+ fallback: deny full-screen permission → verify high-priority notification appears instead
