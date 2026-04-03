## ADDED Requirements

### Requirement: Foreground service lifecycle management
The system SHALL run `ReminderForegroundService` as a persistent foreground service with `START_STICKY` return value, ensuring automatic restart after system kill. The service SHALL display a persistent notification indicating the reminder service is active.

#### Scenario: Service starts on app launch
- **WHEN** Flutter app completes data loading and sends `startService` via MethodChannel
- **THEN** `ReminderForegroundService` starts as a foreground service with a persistent notification, and begins the reminder check loop

#### Scenario: Service survives app kill
- **WHEN** Android system kills the app process
- **THEN** `ReminderForegroundService` is automatically restarted by the system (START_STICKY), reopens the database, and resumes the reminder check loop

#### Scenario: Service stops on user request
- **WHEN** user disables reminders in settings, Flutter sends `stopService` via MethodChannel
- **THEN** `ReminderForegroundService` stops gracefully, cancels the check timer, releases WakeLock, and removes the foreground notification

### Requirement: Periodic reminder check loop
The system SHALL perform a reminder check every 30 seconds using `Handler + HandlerThread` (not the main thread). Each check SHALL query the SQLite database, evaluate task and habit reminder conditions, and trigger alerts when conditions are met.

#### Scenario: Check loop runs on background thread
- **WHEN** the check timer fires
- **THEN** the database query and time calculation execute on a HandlerThread, never blocking the main thread

#### Scenario: Check loop handles database errors gracefully
- **WHEN** a database query fails (e.g., DB locked, file corrupted)
- **THEN** the error is logged, the current check cycle is skipped, and the next check proceeds normally after 30 seconds

### Requirement: Task reminder detection from SQLite
The system SHALL query the `tasks` table for active tasks with reminder settings and determine if a reminder should be triggered, replicating the Dart layer logic exactly.

#### Scenario: First reminder for an upcoming task
- **WHEN** a task has `status IN (0, 1)`, `reminder_dismissed = 0`, `reminder_minutes IS NOT NULL`, `due_time IS NOT NULL`, and `now >= (due_time - reminder_minutes)`
- **THEN** the task is identified as needing a first reminder, marked as `first_sent_{taskId}` in SharedPreferences, and `last_remind_{taskId}` timestamp is recorded

#### Scenario: Continual reminder for unhandled task
- **WHEN** a task has already received its first reminder (`first_sent_{taskId}` exists in SP) AND `now >= last_remind_{taskId} + 30 seconds` AND `now < due_time + 1 hour`
- **THEN** a continual reminder is triggered and `last_remind_{taskId}` is updated

#### Scenario: Continual reminder stops after deadline + 1 hour
- **WHEN** a task's continual reminder would trigger but `now >= due_time + 1 hour`
- **THEN** all reminder state for that task is cleared from SharedPreferences and no more reminders fire

#### Scenario: Snoozed task triggers when snooze expires
- **WHEN** a task has a snooze entry `snooze_{taskId}` in SharedPreferences AND `now >= snooze_time`
- **THEN** the reminder fires, the snooze entry is cleared, and normal reminder flow resumes

#### Scenario: Dismissed task is permanently skipped
- **WHEN** a task has `reminder_dismissed = 1` in the database
- **THEN** the task is excluded from the SQL query and no reminder is ever triggered

### Requirement: Habit reminder detection from SQLite
The system SHALL query the `habits` table for enabled habits and evaluate reminder conditions based on trigger type, schedule type, and time calculations.

#### Scenario: Fixed-time habit triggers at the correct time
- **WHEN** a habit has `trigger_type = 'fixed'`, `schedule_type = 'weekdays'`, today is a weekday (Mon-Fri), and `now` is within 1 minute after the trigger time
- **THEN** the habit reminder fires, but NOT if `habit_fixed_{habitId}_{today}` already exists in SharedPreferences (prevents duplicate triggers)

#### Scenario: Clock-in habit uses reference time with advance offset
- **WHEN** a habit has `id = 'habit_clock_in'` with `reference_time = '09:00'` and `advance_minutes = 10`
- **THEN** the trigger time is calculated as `09:00 - 10 minutes = 08:50`

#### Scenario: Interval habit triggers during work hours
- **WHEN** a habit has `trigger_type = 'interval'`, `interval_minutes = 60`, `id IN ('habit_water', 'habit_stretch')`, and the work time range is 09:00-18:00 (from clock_in/clock_out reference times)
- **THEN** trigger times are generated at 09:00, 10:00, 11:00, ..., 18:00, and a reminder fires when `now` is within ±1 minute of any trigger point, provided no trigger occurred in the last `interval_minutes` minutes (checked via SP `habit_last_{habitId}`)

#### Scenario: Weekday-only habit skips weekends
- **WHEN** a habit has `schedule_type = 'weekdays'` and today is Saturday or Sunday
- **THEN** no reminder check is performed for that habit

#### Scenario: Daily habit triggers every day
- **WHEN** a habit has `schedule_type = 'daily'`
- **THEN** the reminder check is performed regardless of the day of week

### Requirement: Work time range calculation
The system SHALL determine work hours by querying `habit_clock_in` and `habit_clock_out` habits' `reference_time` fields. Default to 09:00-18:00 if clock habits are not configured or disabled.

#### Scenario: Work time from enabled clock habits
- **WHEN** `habit_clock_in` has `reference_time = '08:30'` and is enabled, and `habit_clock_out` has `reference_time = '17:30'` and is enabled
- **THEN** work time range is (8, 17), meaning 08:00-17:00

#### Scenario: Default work time when clock habits disabled
- **WHEN** neither `habit_clock_in` nor `habit_clock_out` is enabled
- **THEN** work time range defaults to (9, 18)

### Requirement: Reminder state management via SharedPreferences
The system SHALL use a dedicated SharedPreferences file (`reminder_state.xml`) to track all transient reminder state, with automatic cleanup of stale entries.

#### Scenario: State cleanup runs periodically
- **WHEN** the check loop runs and `last_cleanup` timestamp is more than 1 hour ago
- **THEN** all `first_sent_*`, `last_remind_*`, `snooze_*` entries older than 24 hours are deleted, all `habit_fixed_*` entries for dates before today are deleted, and `last_cleanup` is updated

#### Scenario: Concurrent state with Flutter layer
- **WHEN** Flutter sends `clearReminderState(taskId)` via MethodChannel
- **THEN** all `first_sent_{taskId}`, `last_remind_{taskId}`, `snooze_{taskId}` entries are removed from SharedPreferences immediately
