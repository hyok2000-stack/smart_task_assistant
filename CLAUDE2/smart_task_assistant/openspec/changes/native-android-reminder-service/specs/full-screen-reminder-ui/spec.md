## ADDED Requirements

### Requirement: Full-screen reminder activity for lock screen
The system SHALL display a full-screen activity (`FullScreenReminderActivity`) when a reminder triggers and the app is not in the foreground. The activity SHALL be visible over the lock screen with `showWhenLocked` and `turnScreenOn` attributes.

#### Scenario: Task reminder shows on lock screen
- **WHEN** a task reminder triggers and the app is in the background or the screen is locked
- **THEN** the screen turns on (if locked), the full-screen activity appears showing task title, due time description, priority badge, assignee (if any), and action buttons: [10分钟后] [30分钟后] [1小时后] [不再提醒]

#### Scenario: Habit reminder shows on lock screen
- **WHEN** a habit reminder triggers and the app is in the background or the screen is locked
- **THEN** the full-screen activity appears showing habit icon, title, voice text, progress bar (for non-clock habits with today's completion count), and contextually appropriate action buttons

#### Scenario: Clock habit shows simplified UI
- **WHEN** a clock-in or clock-out habit reminder triggers
- **THEN** the activity shows only the habit icon, title, reminder text, and a single [知道了] button (no completion tracking, no progress bar)

#### Scenario: Activity habit shows completion UI
- **WHEN** a water or stretch habit reminder triggers
- **THEN** the activity shows the habit icon, title, progress bar with today's target and completed count, [不再提醒] and [已完成] buttons, and snooze options: [5分钟后] [15分钟后] [30分钟后]

### Requirement: User actions update reminder state
The FullScreenReminderActivity SHALL handle user interactions and persist state changes to both SharedPreferences and the SQLite database.

#### Scenario: User selects snooze duration
- **WHEN** user taps [10分钟后], [30分钟后], or [1小时后]
- **THEN** SharedPreferences entry `snooze_{id}` is set to `now + N minutes`, the activity finishes, and the reminder will re-fire after the snooze period

#### Scenario: User dismisses task reminder permanently
- **WHEN** user taps [不再提醒] on a task reminder
- **THEN** the database is updated: `UPDATE tasks SET reminder_dismissed = 1 WHERE id = ?`, all SP state for that task is cleared, and the activity finishes

#### Scenario: User marks habit as completed
- **WHEN** user taps [已完成] on an activity habit reminder
- **THEN** a new record is inserted into `habit_logs` table with `habit_id`, `count = 1`, `status = 0`, and `completed_at = now`, the activity finishes, and the event is sent to Flutter via EventChannel

#### Scenario: User closes without action
- **WHEN** user presses back or swipes to dismiss the activity (no explicit action)
- **THEN** for tasks: `snooze_{id}` is set to `now + 30 seconds` (continual reminder behavior); for habits: the activity simply finishes

#### Scenario: Action events propagate to Flutter
- **WHEN** any user action completes in the FullScreenReminderActivity
- **THEN** an event is sent via EventChannel with `{id, type, action, snoozeMinutes?}` so Flutter can synchronize its state

### Requirement: Android 14+ full-screen permission fallback
The system SHALL detect whether full-screen notification permission is granted and fall back gracefully when not available.

#### Scenario: Full-screen permission granted
- **WHEN** `NotificationManager.canUseFullScreenIntent()` returns true (or API < 34)
- **THEN** the reminder launches as a full-screen activity directly

#### Scenario: Full-screen permission denied on Android 14+
- **WHEN** the app targets API 34+ and full-screen permission is not granted
- **THEN** a high-priority notification is posted instead (IMPORTANCE_HIGH, with sound, vibration, and action buttons), and tapping the notification opens the FullScreenReminderActivity

### Requirement: Visual design consistency with Flutter theme
The FullScreenReminderActivity SHALL use a gradient background matching the app's loading screen (`#667EEA` → `#764BA2`) and color-coded elements matching `AppTheme`.

#### Scenario: Priority badge colors match Flutter theme
- **WHEN** a task reminder displays its priority
- **THEN** high priority uses `#DC2626` (Red600), medium uses `#EA580C` (Orange600), low uses `#059669` (Emerald600), matching `AppTheme.highPriorityColor`, `mediumPriorityColor`, `lowPriorityColor`

#### Scenario: Habit icon background colors match Flutter theme
- **WHEN** a habit reminder displays
- **THEN** habit_water uses `#3B82F6` (Blue), habit_stretch uses `#10B981` (Green), habit_clock_in uses `#F59E0B` (Amber), habit_clock_out uses `#EF4444` (Red), matching `HabitReminderDialog._getHabitColor()`
