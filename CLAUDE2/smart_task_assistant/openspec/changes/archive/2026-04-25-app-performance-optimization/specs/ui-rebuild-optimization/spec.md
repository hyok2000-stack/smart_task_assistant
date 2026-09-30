## ADDED Requirements

### Requirement: Filtered task lists cached in Provider
`TaskProvider` SHALL cache the results of filtered task lists (completed tasks, active tasks, overdue tasks) and only recompute them when the underlying `_tasks` list changes. Build methods SHALL read from cached lists, not perform `.where()` filtering.

#### Scenario: Build method reads completed count
- **WHEN** a widget reads `provider.completedTasks` (cached getter)
- **THEN** it returns the pre-computed list without iterating `_tasks`

#### Scenario: Task data changes
- **WHEN** a task is added, updated, or deleted
- **THEN** cached filter lists are recomputed once before `notifyListeners()`

### Requirement: Home page clock update isolated from page rebuild
The 1-second timer that updates the time display on the home page SHALL NOT trigger `setState` on the entire page. It SHALL use a `ValueNotifier` + `ValueListenableBuilder` (or equivalent) scoped to only the time display widget.

#### Scenario: Clock updates every second
- **WHEN** the 1-second timer fires
- **THEN** only the time display Text widget rebuilds, not the task list, progress card, or completed section

### Requirement: BackdropFilter.blur removed from home page
The home page search bar SHALL NOT use `BackdropFilter` with `ImageFilter.blur`. It SHALL use a static semi-transparent background color instead.

#### Scenario: Search bar renders
- **WHEN** the "All Tasks" page renders the search bar
- **THEN** it uses `Container(color: Colors.white.withOpacity(0.85))` or equivalent, not `BackdropFilter`

### Requirement: Home page uses scoped Consumers
The home page "Today" tab SHALL NOT wrap the entire page in a single `Consumer<TaskProvider>`. Each logical section (progress card, task list, completed section) SHALL have its own Consumer or use `Selector` to limit rebuild scope.

#### Scenario: Task list changes
- **WHEN** a single task is completed
- **THEN** only the task list section and completed section rebuild, not the progress card or weather widget
