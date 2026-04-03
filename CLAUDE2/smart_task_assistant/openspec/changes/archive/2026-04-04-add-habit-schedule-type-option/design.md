## Context

当前习惯系统已经支持 `scheduleType` 字段（`weekdays` 或 `daily`），但 UI 层没有暴露这个选项。提醒检查逻辑 (`HabitService.shouldTriggerReminder`) 已经正确实现工作日过滤：

```dart
if (habit.scheduleType == 'weekdays' && !_isWeekday(now)) {
  return false;
}
```

用户无法通过界面修改这个设置，导致所有习惯都固定为工作日提醒。

## Goals / Non-Goals

**Goals:**
- 在习惯设置对话框中添加"提醒范围"选择器
- 支持"工作日"和"自然日"两个选项
- 更新国际化文本（中英文）

**Non-Goals:**
- 修改数据库结构（字段已存在）
- 修改提醒检查逻辑（已支持）

## Decisions

### UI 位置选择

将"提醒范围"选择器放在习惯设置对话框的"时间设置"部分，位于"间隔时间"下方：

```
┌─────────────────────────────────────────┐
│  时间设置                               │
├─────────────────────────────────────────┤
│  间隔时间: [60] 分钟                     │
│  提醒范围: [工作日 ▼]                   │
│  • 工作日 (周一到周五)                   │
│  • 自然日 (每天)                         │
└─────────────────────────────────────────┘
```

**理由：** 与时间设置相关联，用户在配置间隔时间时自然考虑提醒范围。

### 默认值选择

所有预设习惯保持 `scheduleType = 'weekdays'` 作为默认值。

**理由：** 大多数工作相关习惯（喝水、活动）在工作日使用更常见，保留现有行为避免用户困扰。

### 国际化方案

使用现有的 `AppLocalizations` 系统添加翻译键：

| 键名 | 中文 | 英文 |
|------|------|------|
| `habitScheduleType` | 提醒范围 | Reminder Range |
| `habitScheduleTypeWeekdays` | 工作日 | Weekdays |
| `habitScheduleTypeDaily` | 自然日 | Daily |

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 用户可能选择错误的提醒范围 | 在选项中添加说明文字：工作日（周一到周五）、自然日（每天） |
| 现有习惯需要重新配置 | 保持默认值为 weekdays，现有行为不变 |

## Migration Plan

无需数据迁移。字段已存在，默认值不变，只需更新 UI 暴露选项。

## Open Questions

无。