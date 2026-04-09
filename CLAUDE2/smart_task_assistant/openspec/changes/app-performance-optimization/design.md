## Context

当前 app 的性能瓶颈分布在三个层面：

1. **Provider 数据层**：`TaskProvider.updateTask()` 每次操作执行两次 `getAllTasks()` 全表扫描（一次获取旧数据对比，一次刷新内存列表）。`HabitProvider` 每 30 秒无条件 `notifyListeners()`。`_updateTodayProgress()` 对每个有目标的习惯单独查询 `habit_logs`（N+1 问题）。

2. **UI 构建层**：首页 `_buildTodayPage` 用单个 `Consumer<TaskProvider>` 包裹整个页面。每次 provider 通知变化，触发 `.where()` 遍历全部任务 3-4 次、`ImageFilter.blur` GPU 模糊运算。`withOpacity()` 每帧创建新 Color 对象。1 秒时钟 Timer 通过 `setState` 触发全页重建。

3. **定时器/日志层**：`ReminderService` 每 10 秒遍历全部任务+习惯，输出 85+ 条 `debugPrint`。`debugPrint` 在 debug 模式下是同步 I/O 操作。

## Goals / Non-Goals

**Goals:**
- 勾选任务/完成习惯时消除可感知的卡顿（< 16ms 帧时间）
- 减少不必要的 UI 重建次数
- 降低后台定时器对主线程的占用
- 首页滚动 60fps 流畅

**Non-Goals:**
- 不重写为 BLoC/Riverpod 等其他状态管理方案（保持 Provider）
- 不引入新的第三方依赖
- 不修改数据库 schema 版本（仅添加索引）
- 不改变现有业务逻辑和用户交互流程

## Decisions

### D1: Provider 增量更新（内存直接操作）

**决策**：`updateTask()` 不再 reload 全表，改为在内存 `_tasks` 列表中直接替换目标条目。

**当前流程**：
```
updateTask(task) → getAllTasks() → db.update → getAllTasks() → _refreshTaskLists → notifyListeners
```

**优化后**：
```
updateTask(task) → db.update → _tasks[index] = task → _refreshTaskLists → notifyListeners
```

**理由**：全表 reload 是最大瓶颈。内存列表已持有完整数据，更新后直接替换即可。仅在 app 启动时从 DB 全量加载一次。

**例外**：周期任务完成时需要创建新任务并插入列表，此时保留 `getAllTasks()` 或改为手动插入。

**替代方案**：
- 使用 `Selector` 替代 `Consumer` → 改动面大，且不解决 Provider 层全表 reload 问题
- 使用 Isolate 做数据库操作 → 增加复杂度，当前数据量不需要

### D2: HabitProvider 按需通知 + 批量查询

**决策**：移除 30 秒无条件 `notifyListeners()` Timer。改为仅在 CRUD 操作完成后通知。`_updateTodayProgress()` 改为单次 SQL 查询获取所有习惯的今日完成数。

**理由**：无条件 Timer 浪费 CPU 且触发不必要的 UI 重建。习惯的 UI 更新（如进度条）应在数据变化时触发，而非定时轮询。

**替代方案**：
- 保留 Timer 但加 dirty flag → 增加复杂度，不如直接在 CRUD 后通知
- 使用 `select` 精细化重建 → 后续优化方向，本次不引入

### D3: 首页过滤结果缓存到 Provider

**决策**：在 `TaskProvider` 中新增缓存字段 `_filteredCompletedTasks`、`_filteredActiveTasks` 等。仅在 `_tasks` 列表变化时重新计算，build 方法直接读取缓存。

**理由**：当前每次 build 都执行 `.where()` 创建新列表。过滤计算应在数据变化时做一次，而非每次 build 重复做。

**替代方案**：
- 使用 `Selector` → 改动面大，且需要为每种过滤条件写 selector
- 使用 `computed`/`memo` 库 → 引入新依赖

### D4: ImageFilter.blur 替换方案

**决策**：将首页搜索栏的 `BackdropFilter(blur: sigmaX: 10, sigmaY: 10)` 替换为静态半透明背景色。

**理由**：`BackdropFilter.blur` 是 GPU 密集操作，在每次页面重建时重新执行。搜索栏的视觉效果用半透明背景即可实现，用户几乎无法区分。

### D5: 时钟 Timer 隔离

**决策**：将首页的 1 秒 `_updateTime()` Timer 改为仅更新时间显示 Text widget，不触发整个页面的 `setState`。使用 `ValueNotifier<String>` + `ValueListenableBuilder` 隔离重建范围。

**理由**：当前每秒 `setState` 导致整个 `_buildTodayPage` 重建，包含所有任务卡片、过滤计算等，开销巨大。

### D6: ReminderService 日志精简

**决策**：将逐任务逐习惯的 debugPrint 改为摘要模式。每次检查周期只输出一行摘要（检查了 N 个任务、M 个习惯、需要提醒 K 个）。保留关键异常的详细日志。

**理由**：50 个任务 × 5-8 行日志 = 300+ 行输出。debugPrint 在 debug 模式下同步写缓冲区，是实际可测量的开销。

### D7: 数据库索引补充

**决策**：添加缺失的索引，不升级 schema 版本（在 `_onCreate` 和现有迁移逻辑中通过 `CREATE INDEX IF NOT EXISTS` 添加）。

**新增索引**：
- `idx_tasks_status_due_time ON tasks(status, due_time)` — 逾期任务查询
- `idx_habit_logs_habit_date ON habit_logs(habit_id, date(log_date))` — 习惯今日完成数查询

## Risks / Trade-offs

- **[内存缓存一致性]** → Provider 内存数据与数据库不同步的风险。缓解：仅在 app 启动时从 DB 全量加载，后续操作通过 db.write + 内存更新保持一致。周期任务创建等特殊情况保留全量 reload。
- **[过滤缓存过期]** → Provider 缓存的过滤结果可能不反映最新状态。缓解：缓存仅在 `_refreshTaskLists()` 中更新，该函数在每次数据变更后调用。
- **[blur 移除的视觉差异]** → 部分用户可能注意到搜索栏背景效果变化。缓解：使用高品质半透明背景色，视觉差异极小。
