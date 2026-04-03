## ADDED Requirements

### Requirement: Flutter to Kotlin MethodChannel communication
The system SHALL expose a `MethodChannel` named `com.smarttask.smart_task_assistant/reminder` for Flutter-to-Kotlin calls, handled in `MainActivity.kt`.

#### Scenario: Start reminder service
- **WHEN** Flutter invokes `startService()`
- **THEN** `ReminderForegroundService` is started as a foreground service and the method returns `true` on success

#### Scenario: Stop reminder service
- **WHEN** Flutter invokes `stopService()`
- **THEN** `ReminderForegroundService` is stopped and the method returns `true` on success

#### Scenario: Notify app foreground state
- **WHEN** Flutter invokes `notifyAppForeground()`
- **THEN** the Kotlin service records the app state as "foreground" and suppresses FullScreenActivity launches (reminders are left to Flutter layer)

#### Scenario: Notify app background state
- **WHEN** Flutter invokes `notifyAppBackground()`
- **THEN** the Kotlin service records the app state as "background" and enables FullScreenActivity launches for triggered reminders

#### Scenario: Notify data changed
- **WHEN** Flutter invokes `notifyDataChanged(type: String, id: String?)` where type is "task", "habit", or "all"
- **THEN** the Kotlin service clears cached reminder state for the specified type/id, forcing a fresh check on the next cycle

#### Scenario: Clear reminder state for a specific item
- **WHEN** Flutter invokes `clearReminderState(id: String)`
- **THEN** all SharedPreferences entries for that id (`first_sent_{id}`, `last_remind_{id}`, `snooze_{id}`, `habit_last_{id}`, `habit_fixed_{id}_*`) are removed

#### Scenario: Request full-screen permission
- **WHEN** Flutter invokes `requestFullScreenPermission()`
- **THEN** if Android 14+ (API 34+) and permission not granted, the system settings page for the app's full-screen intent permission is opened; returns `true` if permission already granted or API < 34

#### Scenario: Check service running state
- **WHEN** Flutter invokes `isServiceRunning()`
- **THEN** returns `true` if `ReminderForegroundService` is currently running, `false` otherwise

### Requirement: Kotlin to Flutter EventChannel communication
The system SHALL expose an `EventChannel` named `com.smarttask.smart_task_assistant/reminder_events` for Kotlin-to-Flutter event streaming.

#### Scenario: Reminder shown event
- **WHEN** the Kotlin service triggers a reminder (either FullScreenActivity or notification)
- **THEN** an event `{id: "task_xxx", type: "task", action: "shown"}` is sent to Flutter, so Flutter can mark it as shown and avoid duplicate dialog

#### Scenario: Reminder snoozed event
- **WHEN** user selects a snooze option in FullScreenReminderActivity
- **THEN** an event `{id: "xxx", type: "task", action: "snoozed", snoozeMinutes: 10}` is sent to Flutter

#### Scenario: Reminder dismissed event
- **WHEN** user taps "不再提醒" in FullScreenReminderActivity
- **THEN** an event `{id: "xxx", type: "task", action: "dismissed"}` is sent to Flutter, so Flutter updates the task's `reminder_dismissed` field

#### Scenario: Habit completed event
- **WHEN** user taps "已完成" in FullScreenReminderActivity for a habit
- **THEN** an event `{id: "habit_water", type: "habit", action: "completed"}` is sent to Flutter, so Flutter logs the habit completion

#### Scenario: Flutter not attached when event fires
- **WHEN** an event is produced but no Flutter listener is attached (e.g., engine not running)
- **THEN** the event is stored in a buffer (max 10 entries) and replayed when Flutter re-attaches; oldest events are dropped if buffer overflows

### Requirement: Lifecycle integration in main.dart
The `main.dart` SHALL be modified to initialize the MethodChannel/EventChannel, notify the native layer of lifecycle changes, and handle incoming events.

#### Scenario: Channels initialized on app start
- **WHEN** `_MyAppState.initState()` runs
- **THEN** MethodChannel and EventChannel are set up, but `startService()` is not called until data loading completes

#### Scenario: Service started after data load
- **WHEN** `_loadData()` completes successfully
- **THEN** `startService()` is called, `notifyAppForeground()` is called, and EventChannel listener begins receiving events

#### Scenario: App resumes from background
- **WHEN** `didChangeAppLifecycleState` receives `AppLifecycleState.resumed`
- **THEN** `notifyAppForeground()` is called via MethodChannel

#### Scenario: App enters background
- **WHEN** `didChangeAppLifecycleState` receives `AppLifecycleState.paused`
- **THEN** `notifyAppBackground()` is called via MethodChannel

#### Scenario: Event handling delegates to providers
- **WHEN** an event `{action: "completed", id: "xxx", type: "habit"}` is received
- **THEN** `habitProvider.logCompletion(id)` is called to sync the state
