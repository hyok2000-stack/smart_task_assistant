## ADDED Requirements

### Requirement: ReminderService summary logging
`ReminderService._checkReminders()` SHALL output at most 3-5 lines of debug log per check cycle: one summary line for tasks (checked N, reminded K), one for habits (checked M, reminded J), and lines only for tasks/habits that actually need reminding. It SHALL NOT log per-task/per-habit details for items that don't need reminding.

#### Scenario: 50 tasks checked, 1 needs reminding
- **WHEN** `_checkReminders()` runs with 50 tasks
- **THEN** output is approximately 4 lines: start marker, task summary, habit summary, end marker — NOT 300+ lines

#### Scenario: A task actually triggers a reminder
- **WHEN** a specific task needs reminding
- **THEN** the task's title and key parameters are logged (this is a valid detail log)

### Requirement: ReminderService timer interval preserved
The 10-second timer interval for `ReminderService` SHALL be preserved. The optimization is in reducing per-check overhead, not changing the interval.

#### Scenario: Timer frequency unchanged
- **WHEN** app is in foreground
- **THEN** reminder check runs every 10 seconds as before
