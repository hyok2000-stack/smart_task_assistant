## 1. Provider 层优化 — TaskProvider 增量更新

- [ ] 1.1 修改 `TaskProvider.updateTask()`：移除两次 `getAllTasks()` 调用，改为 `_tasks[index] = task` 内存直接替换，保留 `_refreshTaskLists()` 和 `notifyListeners()`
- [ ] 1.2 处理周期任务特殊分支：当 `_createRecurringTask` 触发时，改为 `_tasks.insert(0, newTask)` 手动插入新任务到内存列表，避免全量 reload
- [ ] 1.3 修改 `TaskProvider.completeTask()` 和 `updateTaskStatus()`：同样改为内存增量更新
- [ ] 1.4 在 `TaskProvider` 中新增缓存字段：`_cachedCompletedTasks`、`_cachedActiveTasks`、`_cachedOverdueTasks`，在 `_refreshTaskLists()` 中计算并缓存
- [ ] 1.5 将首页中所有 `provider.tasks.where(...)` / `provider.todayTasks.where(...)` 替换为读取 Provider 缓存的 getter（如 `provider.completedTasks`、`provider.activeTasks`）

## 2. Provider 层优化 — HabitProvider

- [ ] 2.1 移除 `HabitProvider` 中 30 秒无条件 `notifyListeners()` 的 Timer
- [ ] 2.2 修改 `_updateTodayProgress()`：将 N 次单独的 `getHabitTodayCount()` 查询合并为一次批量 SQL 查询 `SELECT habit_id, COUNT(*) FROM habit_logs WHERE date(log_date) = today GROUP BY habit_id`
- [ ] 2.3 在 `HabitProvider` 中添加批量查询方法 `getHabitTodayCountsBatch(List<String> habitIds)` 到 `DatabaseHelper`
- [ ] 2.4 修改 `HabitProvider.updateHabit()`：改为内存增量更新，移除双重 `getAllHabits()` 调用

## 3. UI 层优化 — 首页重建范围

- [ ] 3.1 将 `_buildTodayPage` 中的单个 `Consumer<TaskProvider>` 拆分为多个独立 Consumer：进度卡片、任务列表、已完成分组各一个
- [ ] 3.2 时钟 Timer 隔离：将 `_updateTime()` 从 `setState` 改为 `ValueNotifier<String>` + `ValueListenableBuilder`，仅重建时间显示 Text
- [ ] 3.3 移除 "All Tasks" 页面搜索栏的 `BackdropFilter(blur: ImageFilter.blur(sigmaX: 10, sigmaY: 10))`，替换为 `Container(color: Colors.white.withOpacity(0.85))` 半透明背景

## 4. ReminderService 日志精简

- [ ] 4.1 将 `_checkTaskReminders()` 中逐任务的 debugPrint 改为摘要模式：循环结束后输出一行 `"[任务检查] 已检查 $checkedCount 个，需要提醒 $needRemindCount 个"`，仅对需要提醒的任务输出详细日志
- [ ] 4.2 将 `_shouldShowReminder()` 中逐行 debugPrint 精简为仅在返回 `true` 时输出关键信息
- [ ] 4.3 将 `_checkHabitReminders()` 同样改为摘要模式
- [ ] 4.4 保留异常和错误情况的详细日志不变

## 5. 数据库索引

- [ ] 5.1 在 `DatabaseHelper._onCreate()` 中添加 `CREATE INDEX IF NOT EXISTS idx_tasks_status_due_time ON tasks(status, due_time)`
- [ ] 5.2 在 `DatabaseHelper._onCreate()` 中添加 `CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, date(log_date))`
- [ ] 5.3 在 `DatabaseHelper._onUpgrade()` 的现有迁移逻辑中添加相同的 `CREATE INDEX IF NOT EXISTS` 语句（不升级 schema version）

## 6. 验证

- [ ] 6.1 Flutter analyze 无新 error
- [ ] 6.2 编译 release APK 确认无运行时异常
- [ ] 6.3 Profile 模式下对比优化前后：勾选任务时的帧时间、首页 rebuild 次数
