## ADDED Requirements

### Requirement: Task update uses in-memory replacement
`TaskProvider.updateTask()` SHALL update the target task in the in-memory `_tasks` list directly, without reloading all tasks from the database. The database write SHALL still occur, but the subsequent refresh SHALL be a targeted in-memory update of the modified entry only.

#### Scenario: Complete a task
- **WHEN** user completes a task via `completeTask(id)`
- **THEN** the provider updates the task in memory (`_tasks[index] = updatedTask`), writes to database, and calls `notifyListeners()` — without calling `getAllTasks()`

#### Scenario: Update task with recurring rule completion
- **WHEN** a recurring task is completed and a new task is created
- **THEN** the provider MAY use `getAllTasks()` reload for this specific case, as a new task is inserted that doesn't exist in memory

### Requirement: HabitProvider notifies only on data change
`HabitProvider` SHALL NOT use a periodic `Timer` to unconditionally call `notifyListeners()`. Notifications SHALL only be triggered after CRUD operations that modify data.

#### Scenario: No data changes for 5 minutes
- **WHEN** no habit CRUD operations occur for 5 minutes
- **THEN** `notifyListeners()` is NOT called during that period

#### Scenario: User completes a habit
- **WHEN** user logs a habit completion
- **THEN** `notifyListeners()` is called exactly once after the data update completes

### Requirement: Habit progress uses batch query
`HabitProvider._updateTodayProgress()` SHALL use a single SQL query to retrieve today's completion counts for ALL habits with targets, instead of making N individual queries.

#### Scenario: 10 habits with targets
- **WHEN** `_updateTodayProgress()` runs with 10 habits that have target counts
- **THEN** it executes exactly 1 SQL query (not 10) to get all completion counts

### Requirement: Database indexes for common queries
The database SHALL have indexes on columns used by frequent queries: `(status, due_time)` on tasks, and `(habit_id, date)` on habit_logs.

#### Scenario: App starts with existing database
- **WHEN** app opens an existing database (schema migration)
- **THEN** indexes are created via `CREATE INDEX IF NOT EXISTS` without incrementing the schema version
