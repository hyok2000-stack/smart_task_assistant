## MODIFIED Requirements

### Requirement: Parse due_time from SQLite into epoch millis

The system SHALL parse the `due_time` string stored in SQLite by the Flutter layer into epoch milliseconds using a robust regex-based extraction approach. The parser SHALL handle all ISO 8601 variants produced by Dart's `DateTime.toIso8601String()`, including:
- `"2026-04-03T14:00:00.000"` (3 fractional digits)
- `"2026-04-03T14:00:00.000000"` (6 fractional digits, microseconds)
- `"2026-04-03T14:00:00"` (no fractional digits)
- `"2026-04-03T14:00:00.000Z"` (with UTC suffix)
- `"2026-04-03T14:00:00.000+08:00"` (with timezone offset)
- `"2026-04-03 14:00:00"` (space separator)

The parser SHALL use regex `"""(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})"""` to extract components and construct a `Calendar` instance in the default timezone. The previous `SimpleDateFormat` chain SHALL be retained as a fallback.

#### Scenario: Standard Dart ISO 8601 output
- **WHEN** `due_time` is `"2026-04-03T14:00:00.000"`
- **THEN** the parser SHALL return epoch millis corresponding to April 3, 2026, 14:00:00 in local timezone

#### Scenario: ISO string with microseconds
- **WHEN** `due_time` is `"2026-04-03T14:00:00.123456"`
- **THEN** the parser SHALL return epoch millis corresponding to April 3, 2026, 14:00:00 in local timezone (fractional seconds ignored)

#### Scenario: ISO string with timezone suffix
- **WHEN** `due_time` is `"2026-04-03T14:00:00.000+08:00"`
- **THEN** the parser SHALL return epoch millis by extracting components with regex and using local timezone

#### Scenario: ISO string with no fractional seconds
- **WHEN** `due_time` is `"2026-04-03T14:00:00"`
- **THEN** the parser SHALL return epoch millis corresponding to April 3, 2026, 14:00:00 in local timezone

#### Scenario: Unparseable string
- **WHEN** `due_time` is `"not-a-date"` or empty
- **THEN** the parser SHALL return null

### Requirement: Diagnostic logging for task reminder checks

The system SHALL log diagnostic information at `Log.d` level during task reminder checks in `checkAll()`, including:
- Number of active tasks found by `queryActiveTasks()`
- For each task: id, title, dueTime string, reminderMinutes, and `shouldTriggerTask()` result
- Any parse failures in `parseDueTimeMillis()` at `Log.w` level

#### Scenario: Tasks found during check
- **WHEN** `checkAll()` queries active tasks and finds N tasks
- **THEN** system SHALL log "Found N active tasks for reminder check" and per-task details

#### Scenario: Task trigger evaluation
- **WHEN** `shouldTriggerTask()` evaluates a task
- **THEN** system SHALL log the task title, parsed dueTime, calculated reminderTime, and final trigger decision (true/false)

#### Scenario: Parse failure
- **WHEN** `parseDueTimeMillis()` cannot parse a due_time string
- **THEN** system SHALL log at WARN level: "Failed to parse due_time: {value}"
