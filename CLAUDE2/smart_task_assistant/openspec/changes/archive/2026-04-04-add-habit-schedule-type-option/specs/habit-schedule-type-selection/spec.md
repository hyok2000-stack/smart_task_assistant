## ADDED Requirements

### Requirement: User can select habit schedule type
The system SHALL allow users to select the schedule type for each habit, with options for "weekdays" (工作日) and "daily" (自然日).

#### Scenario: User selects weekdays schedule type
- **WHEN** user opens habit settings dialog
- **THEN** system displays "提醒范围" (Reminder Range) option with dropdown
- **AND** dropdown contains "工作日" (Weekdays) and "自然日" (Daily) options
- **AND** default selection is "工作日"
- **AND** user can select a different option

#### Scenario: User saves habit with new schedule type
- **WHEN** user selects "自然日" and saves habit settings
- **THEN** system updates habit's `scheduleType` field to "daily"
- **AND** habit reminders will trigger on all days (including weekends)

#### Scenario: Habit with weekdays schedule type
- **WHEN** habit `scheduleType` is "weekdays"
- **THEN** system SHALL NOT trigger reminders on Saturday (weekday 7) or Sunday (weekday 6)

#### Scenario: Habit with daily schedule type
- **WHEN** habit `scheduleType` is "daily"
- **THEN** system SHALL trigger reminders on all days regardless of weekday