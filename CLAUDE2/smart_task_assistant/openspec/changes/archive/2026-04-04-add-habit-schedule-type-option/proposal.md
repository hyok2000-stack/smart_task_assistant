## Why

目前习惯的提醒范围固定为"工作日"（周一到周五），但用户可能需要在周末也收到喝水、起身活动等习惯提醒。当前数据模型和检查逻辑已经支持 `scheduleType` 字段，但 UI 层没有暴露这个选项，导致用户无法自定义提醒范围。

## What Changes

- 在习惯设置对话框中添加"提醒范围"选项，可选择"工作日"或"自然日"
- 更新国际化文本，支持中英文
- 确保所有预设习惯都有正确的 `scheduleType` 默认值

## Capabilities

### New Capabilities

- `habit-schedule-type-selection`: 允许用户为习惯选择提醒范围（工作日/自然日）

### Modified Capabilities

无 - 现有检查逻辑已支持，无需修改需求

## Impact

**受影响代码：**
- `lib/widgets/habit_settings_dialog.dart` - 添加 scheduleType 选择器 UI
- `lib/utils/app_localizations.dart` - 添加国际化文本
- `lib/models/habit.dart` - 确保 PresetHabits 中的默认值正确

**不受影响：**
- `lib/services/habit_service.dart` - 检查逻辑已支持 `scheduleType` 字段
- 数据库结构 - `schedule_type` 字段已存在