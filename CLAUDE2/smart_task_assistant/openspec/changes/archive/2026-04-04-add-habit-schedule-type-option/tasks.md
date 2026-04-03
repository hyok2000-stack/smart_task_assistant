## 1. 国际化文本

- [x] 1.1 在 `lib/utils/app_localizations.dart` 中添加中文翻译键
  - `habitScheduleType`: 提醒范围
  - `habitScheduleTypeWeekdays`: 工作日
  - `habitScheduleTypeDaily`: 自然日
- [x] 1.2 在 `lib/utils/app_localizations.dart` 中添加英文翻译键
  - `habitScheduleType`: Reminder Range
  - `habitScheduleTypeWeekdays`: Weekdays
  - `habitScheduleTypeDaily`: Daily

## 2. 习惯设置对话框 UI

- [x] 2.1 在 `lib/widgets/habit_settings_dialog.dart` 的 `_buildTimeSection` 方法中添加提醒范围选择器
  - 位于"间隔时间"下方
  - 使用 DropdownButton 或类似组件
  - 选项包括"工作日"和"自然日"
- [x] 2.2 确保 scheduleType 变化时正确更新 `_editedHabit` 对象
- [x] 2.3 在选项旁添加说明文字（工作日：周一到周五，自然日：每天）

## 3. 测试验证

- [x] 3.1 验证习惯设置对话框显示提醒范围选项
- [x] 3.2 验证选择"自然日"后，习惯在周末也能触发提醒
- [x] 3.3 验证选择"工作日"后，习惯在周末不会触发提醒
- [x] 3.4 验证预设习惯默认值为"工作日"