## Why

用户反馈 APP 操作卡顿，主要表现为：勾选任务时明显延迟、首页滚动掉帧、后台定时器频繁触发导致整体响应变慢。根因分析定位到三个层面的问题：Provider 层每次操作触发双重数据库全表扫描 + 全量内存过滤；UI 层 Consumer 粒度过粗导致不必要的整页重建，build 方法中包含重度运算（ImageFilter.blur、反复 .where().toList()）；定时器层存在多个高频 Timer（1s/10s/30s）叠加运行，且 reminder_service 每 10 秒输出 85+ 条 debugPrint。随着任务/习惯数据增长，这些问题会线性恶化。

## What Changes

- 优化 `TaskProvider.updateTask()`：移除双重 `getAllTasks()` 全表扫描，改为内存中直接更新对应任务条目
- 优化 `HabitProvider`：移除 30 秒无条件 `notifyListeners()`，改为仅在数据变化时通知；合并 `_updateTodayProgress()` 中的 N+1 数据库查询为批量查询
- 优化首页 `home_screen.dart`：缩小 `Consumer<TaskProvider>` 包裹粒度，将过滤计算结果缓存到 Provider 层而非每次 build 重新计算；移除 `ImageFilter.blur` 高开销模糊效果
- 优化 `ReminderService`：大幅减少 debugPrint 输出，仅在关键节点保留日志；将遍历日志从逐条打印改为摘要输出
- 优化 `DatabaseHelper`：为高频查询条件添加缺失的数据库索引
- 将 `home_screen` 的 1 秒时钟 Timer 限制为仅更新时间显示组件，不触发整页 setState

## Capabilities

### New Capabilities
- `provider-optimized-updates`: Provider 层增量更新机制，避免每次操作触发全量数据库重载和全量内存过滤，改为内存中直接更新变化条目
- `ui-rebuild-optimization`: UI 层重建优化，缩小 Consumer 粒度、缓存过滤结果、移除 build 中的重度运算
- `timer-log-cleanup`: 定时器频率调整和日志清理，减少后台开销

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **Flutter 层（Provider）**: `task_provider.dart`（updateTask/completeTask 改为内存增量更新）、`habit_provider.dart`（移除无条件 notifyListeners、合并 N+1 查询）
- **Flutter 层（UI）**: `home_screen.dart`（Consumer 粒度拆分、移除 blur、缓存过滤结果）
- **Flutter 层（Service）**: `reminder_service.dart`（精简日志输出）
- **数据库**: `database_helper.dart`（新增索引，无需 schema 版本升级）
- **兼容性**: 无破坏性变更，所有改动为内部优化，不影响用户数据和 API
