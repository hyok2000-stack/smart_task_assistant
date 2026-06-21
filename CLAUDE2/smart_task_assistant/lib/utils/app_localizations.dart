import 'package:flutter/material.dart';
import '../main.dart' show AppSettings, appSettings;

/// 应用国际化工具类
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  bool get isZh => locale.languageCode == 'zh';

  // 通用
  String get appName => isZh ? '智能任务助手' : 'Smart Task Assistant';
  String get loading => isZh ? '加载中...' : 'Loading...';
  String get confirm => isZh ? '确认' : 'Confirm';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get save => isZh ? '保存' : 'Save';
  String get delete => isZh ? '删除' : 'Delete';
  String get edit => isZh ? '编辑' : 'Edit';
  String get add => isZh ? '添加' : 'Add';
  String get search => isZh ? '搜索' : 'Search';
  String get searchHint => isZh ? '搜索任务...' : 'Search tasks...';
  String get noData => isZh ? '暂无数据' : 'No data';
  String get success => isZh ? '成功' : 'Success';
  String get error => isZh ? '错误' : 'Error';
  String get retry => isZh ? '重试' : 'Retry';
  String get loadFailed => isZh ? '加载失败，请重试' : 'Failed to load, tap to retry';
  String get close => isZh ? '关闭' : 'Close';
  String get viewTask => isZh ? '查看任务' : 'View Task';

  // 底部导航
  String get navToday => isZh ? '今天' : 'Today';
  String get navAll => isZh ? '全部' : 'All';
  String get navStats => isZh ? '统计' : 'Stats';
  String get navHabit => isZh ? '习惯' : 'Habits';
  String get navCalendar => isZh ? '日历' : 'Calendar';
  String get navSettings => isZh ? '设置' : 'Settings';

  // 设置标签页
  String get chatAI => isZh ? '智答AI' : 'Chat AI';
  String get general => isZh ? '通用' : 'General';
  String get about => isZh ? '关于' : 'About';

  // 首页
  String get greetingMorning => isZh ? '早上好' : 'Good Morning';
  String get greetingNoon => isZh ? '中午好' : 'Good Noon';
  String get greetingAfternoon => isZh ? '下午好' : 'Good Afternoon';
  String get greetingEvening => isZh ? '晚上好' : 'Good Evening';
  String get greetingNight => isZh ? '夜深了' : 'Good Night';
  String get overdueTasks => isZh ? '逾期任务' : 'Overdue Tasks';
  String get pendingTasks => isZh ? '未完成任务' : 'Pending Tasks';
  String get viewAll => isZh ? '查看全部' : 'View All';
  String get completed => isZh ? '已完成' : 'Completed';
  String get noTasks => isZh ? '暂无任务' : 'No tasks';
  String get allTasksCompleted =>
      isZh ? '今日任务全部完成！' : 'All today\'s tasks completed!';
  String completedTasksMsg(int count) => isZh
      ? '已完成 $count 项任务，干得漂亮！'
      : '$count tasks completed. Great job!';
  String get addTaskHint =>
      isZh ? '点击右下角按钮添加新任务' : 'Tap the button below to add a new task';
  String get aiSuggestion => isZh ? 'AI 智能建议' : 'AI Suggestion';
  String get aiSuggestPriority => isZh ? '建议优先处理' : 'Suggested priority task';
  String get deadline => isZh ? '截止时间' : 'Deadline';
  String get greatJob => isZh
      ? '太棒了！今天没有待处理的任务，享受轻松时光吧！'
      : 'Great! No pending tasks today, enjoy your free time!';

  // 任务状态
  String get statusPending => isZh ? '待处理' : 'Pending';
  String get statusInProgress => isZh ? '进行中' : 'In Progress';
  String get statusCompleted => isZh ? '已完成' : 'Completed';
  String get statusCancelled => isZh ? '已取消' : 'Cancelled';

  // 优先级
  String get priorityHigh => isZh ? '高优先级' : 'High Priority';
  String get priorityMedium => isZh ? '中优先级' : 'Medium Priority';
  String get priorityLow => isZh ? '低优先级' : 'Low Priority';

  // 任务操作
  String get taskComplete => isZh ? '任务已完成' : 'Task completed';
  String get taskDelete => isZh ? '任务已删除' : 'Task deleted';
  String get taskStart => isZh ? '任务已开始' : 'Task started';
  String get taskRestore => isZh ? '任务已恢复' : 'Task restored';
  String get confirmDelete => isZh ? '确认删除' : 'Confirm Delete';
  String get confirmDeleteHint => isZh
      ? '确定要删除这个任务吗？此操作不可撤销。'
      : 'Are you sure you want to delete this task? This action cannot be undone.';
  String get changeStatus => isZh ? '修改状态' : 'Change Status';
  String get editTask => isZh ? '编辑任务' : 'Edit Task';
  String get addTask => isZh ? '添加任务' : 'Add Task';
  String get taskTitle => isZh ? '任务标题' : 'Task Title';
  String get taskContent => isZh ? '任务内容' : 'Task Content';
  String get createTime => isZh ? '创建时间' : 'Created';

  // 周期任务
  String get recurringTask => isZh ? '周期任务' : 'Recurring Task';
  String get recurringTaskCompleteHint => isZh
      ? '周期任务已完成，已自动创建下一期'
      : 'Recurring task completed, next occurrence created';

  // 设置页面
  String get settings => isZh ? '设置' : 'Settings';
  String get appearance => isZh ? '外观' : 'Appearance';
  String get darkMode => isZh ? '深色模式' : 'Dark Mode';
  String get darkModeHint => isZh ? '切换深色/浅色主题' : 'Toggle dark/light theme';
  String get language => isZh ? '语言' : 'Language';
  String get selectLanguage => isZh ? '选择语言' : 'Select Language';
  String get notifications => isZh ? '通知' : 'Notifications';
  String get pushNotifications => isZh ? '推送通知' : 'Push Notifications';
  String get pushNotificationsHint =>
      isZh ? '接收任务提醒通知' : 'Receive task reminders';
  String get clipboardMonitor => isZh ? '剪贴板监视' : 'Clipboard Monitor';
  String get clipboardMonitorHint =>
      isZh ? '粘贴内容时自动弹出任务创建窗口' : 'Auto popup on paste';
  String get aiService => isZh ? 'AI 服务' : 'AI Service';
  String get aiServiceConfig => isZh ? 'AI 服务配置' : 'AI Service Config';
  String get aiServiceConfigHint =>
      isZh ? '配置本地大模型或远程 API' : 'Configure local LLM or remote API';
  String get tagManagement => isZh ? '标签管理' : 'Tag Management';
  String get addTag => isZh ? '添加标签' : 'Add Tag';
  String get tagName => isZh ? '标签名称' : 'Tag Name';
  String get editTag => isZh ? '编辑标签' : 'Edit Tag';
  String get deleteTag => isZh ? '删除标签' : 'Delete Tag';
  String get confirmDeleteTag =>
      isZh ? '确定要删除标签' : 'Are you sure you want to delete tag';
  String get dataManagement => isZh ? '数据' : 'Data';
  String get exportData => isZh ? '导出数据' : 'Export Data';
  String get importData => isZh ? '导入数据' : 'Import Data';
  String get clearAllData => isZh ? '清除所有数据' : 'Clear All Data';
  String get confirmClearData => isZh
      ? '确定要删除所有任务和标签吗？此操作不可恢复。'
      : 'Delete all tasks and tags? This cannot be undone.';
  String get dataCleared => isZh ? '所有数据已清除' : 'All data cleared';
  String get version => isZh ? '版本' : 'Version';
  String get clearData => isZh ? '清除数据' : 'Clear Data';
  String get confirmClear => isZh ? '确认清除' : 'Confirm Clear';
  String get confirmClearHint => isZh
      ? '确定要清除所有数据吗？此操作不可恢复。'
      : 'Are you sure you want to clear all data? This action cannot be undone.';
  String get clearSuccess => isZh ? '清除成功' : 'Clear success';
  String get generalSettings => isZh ? '通用设置' : 'General Settings';
  String get reminderSettings => isZh ? '提醒设置' : 'Reminder Settings';
  String get enableReminder => isZh ? '启用提醒' : 'Enable Reminder';
  String get reminderTime => isZh ? '提醒时间' : 'Reminder Time';
  String get logViewer => isZh ? '日志查看' : 'Log Viewer';
  String get viewLog => isZh ? '查看日志' : 'View Log';
  String get appDescription => isZh ? '应用描述' : 'App Description';
  String get appDescriptionText => isZh
      ? '智能任务助手是一款基于AI的任务管理应用，帮助您高效管理日常任务。'
      : 'Smart Task Assistant is an AI-powered task management app that helps you manage daily tasks efficiently.';
  String get features => isZh ? '功能特性' : 'Features';
  String get feature1 => isZh ? '智能任务识别' : 'Smart task recognition';
  String get feature2 => isZh ? 'AI智能建议' : 'AI intelligent suggestions';
  String get feature3 => isZh ? '多种提醒方式' : 'Multiple reminder methods';
  String get feature4 => isZh ? '数据云端同步' : 'Cloud data sync';
  String get contact => isZh ? '联系我们' : 'Contact Us';
  String get feedback => isZh ? '反馈建议' : 'Feedback';
  String get feedbackHint => isZh ? '帮助我们改进应用' : 'Help us improve';
  String get privacyPolicy => isZh ? '隐私政策' : 'Privacy Policy';
  String get privacyPolicyHint => isZh ? '查看隐私政策' : 'View privacy policy';

  // 导出导入
  String get exportSuccess => isZh ? '已导出' : 'Exported';
  String get importSuccess => isZh ? '已导入' : 'Imported';
  String get tasksAndTags => isZh ? '个任务和' : ' tasks and ';
  String get tags => isZh ? '个标签' : ' tags';
  String get exportFailed => isZh ? '导出失败' : 'Export failed';
  String get importFailed => isZh ? '导入失败' : 'Import failed';
  String get noBackupFound => isZh ? '没有找到备份文件' : 'No backup files found';
  String get selectBackupFile => isZh ? '选择备份文件' : 'Select Backup File';

  // AI 配置
  String get enableAI => isZh ? '启用 AI 服务' : 'Enable AI Service';
  String get enableAIHint =>
      isZh ? '关闭后将使用本地规则引擎' : 'Will use local rule engine when disabled';
  String get selectProvider => isZh ? '选择服务商' : 'Select Provider';
  String get localEngine =>
      isZh ? '本地规则引擎（无需配置）' : 'Local Rule Engine (No config needed)';
  String get testConnection => isZh ? '测试连接' : 'Test Connection';
  String get testing => isZh ? '测试中...' : 'Testing...';
  String get connectionSuccess => isZh ? '连接成功' : 'Connection successful';
  String get connectionFailed => isZh ? '连接失败' : 'Connection failed';
  String get aiConfigSaved => isZh ? 'AI 配置已保存' : 'AI config saved';

  // 统计页面
  String get statistics => isZh ? '统计' : 'Statistics';
  String get todayProgress => isZh ? '今日进度' : 'Today\'s Progress';
  String get weeklyOverview => isZh ? '本周概览' : 'Weekly Overview';
  String get taskDistribution => isZh ? '任务分布' : 'Task Distribution';
  String get completionRate => isZh ? '完成率' : 'Completion Rate';
  String get totalTasks => isZh ? '总任务' : 'Total Tasks';
  String get completedTasks => isZh ? '已完成' : 'Completed';
  String get inProgressTasks => isZh ? '进行中' : 'In Progress';
  String get pendingTasksCount => isZh ? '待处理' : 'Pending';
  String get overdueTasksCount => isZh ? '已逾期' : 'Overdue';

  // 快速添加
  String get quickAddTask => isZh ? '快速添加任务' : 'Quick Add Task';
  String get taskTitleHint => isZh ? '输入任务标题...' : 'Enter task title...';
  String get selectDueTime => isZh ? '选择截止时间' : 'Select deadline';
  String get selectPriority => isZh ? '选择优先级' : 'Select priority';
  String get today => isZh ? '今天' : 'Today';
  String get tomorrow => isZh ? '明天' : 'Tomorrow';
  String get thisWeek => isZh ? '本周' : 'This Week';
  String get nextWeek => isZh ? '下周' : 'Next Week';
  String get noDeadline => isZh ? '无截止时间' : 'No deadline';
  String get customTime => isZh ? '自定义时间' : 'Custom time';

  // 日期
  String get monday => isZh ? '周一' : 'Mon';
  String get tuesday => isZh ? '周二' : 'Tue';
  String get wednesday => isZh ? '周三' : 'Wed';
  String get thursday => isZh ? '周四' : 'Thu';
  String get friday => isZh ? '周五' : 'Fri';
  String get saturday => isZh ? '周六' : 'Sat';
  String get sunday => isZh ? '周日' : 'Sun';

  // 时间相关
  String get daysAgo => isZh ? '天前' : ' days ago';
  String get hoursAgo => isZh ? '小时前' : ' hours ago';
  String get minutesAgo => isZh ? '分钟前' : ' minutes ago';
  String get justNow => isZh ? '刚刚' : 'Just now';
  String get later => isZh ? '后' : ' later';
  String get overdue => isZh ? '已逾期' : 'Overdue';

  // 筛选
  String get filterAll => isZh ? '全部' : 'All';
  String get filterOverdue => isZh ? '已逾期' : 'Overdue';

  // 通知
  String get overdueReminder => isZh ? '逾期任务提醒' : 'Overdue Task Reminder';
  String get noOverdueTasks => isZh ? '暂无逾期任务' : 'No overdue tasks';
  String get view => isZh ? '查看' : 'View';

  // 添加/编辑任务页面
  String get newTask => isZh ? '新建任务' : 'New Task';
  String get taskDetails => isZh ? '任务详情' : 'Task Details';
  String get enterTaskTitle => isZh ? '输入任务标题...' : 'Enter task title...';
  String get enterTaskDetails => isZh ? '输入任务详情...' : 'Enter task details...';
  String get selectDeadline => isZh ? '选择截止时间' : 'Select Deadline';
  String get noReminder => isZh ? '不提醒' : 'No Reminder';
  String get minBefore => isZh ? '分钟前' : ' min before';
  String get hourBefore => isZh ? '1小时前' : '1 hour before';
  String get custom => isZh ? '自定义' : 'Custom';
  String get enterMinutes => isZh ? '输入分钟数' : 'Enter minutes';
  String get priority => isZh ? '优先级' : 'Priority';
  String get priorityLowShort => isZh ? '低' : 'Low';
  String get priorityMediumShort => isZh ? '中' : 'Medium';
  String get priorityHighShort => isZh ? '高' : 'High';
  String get tagsLabel => isZh ? '标签' : 'Tags';
  String get recurringTaskSettings => isZh ? '周期任务' : 'Recurring Task';
  String get setAsRecurring => isZh ? '设为周期任务' : 'Set as recurring task';
  String get autoCreateNext =>
      isZh ? '完成后自动创建新任务' : 'Auto create next task when completed';
  String get off => isZh ? '关闭' : 'Off';
  String get repeatCycle => isZh ? '重复周期' : 'Repeat Cycle';
  String get daily => isZh ? '每天' : 'Daily';
  String get weekly => isZh ? '每周' : 'Weekly';
  String get monthly => isZh ? '每月' : 'Monthly';
  String get taskStatus => isZh ? '任务状态' : 'Task Status';
  String get inProgress => isZh ? '进行中' : 'In Progress';
  String get aiDetected => isZh ? 'AI 智能识别' : 'AI Detection';
  String get timeKeywordDetected => isZh
      ? '检测到时间关键词，建议设置截止时间'
      : 'Time keyword detected, suggest setting deadline';
  String get priorityKeywordDetected => isZh
      ? '检测到优先级关键词，建议设为高优先级'
      : 'Priority keyword detected, suggest high priority';
  String get pleaseEnterTitle => isZh ? '请输入任务标题' : 'Please enter task title';
  String get taskUpdated => isZh ? '任务已更新' : 'Task updated';
  String get reminder => isZh ? '提醒' : 'Reminder';

  // 标签默认值
  String get tagWork => isZh ? '工作' : 'Work';
  String get tagPersonal => isZh ? '个人' : 'Personal';
  String get tagUrgent => isZh ? '紧急' : 'Urgent';
  String get tagStudy => isZh ? '学习' : 'Study';
  String get defaultTag => isZh ? '默认' : 'Default';

  // 数据导出导入
  String get exportedCount => isZh ? '✓ 已导出' : '✓ Exported';
  String get importedCount => isZh ? '已导入' : 'Imported';
  String get saveLocation => isZh ? '保存位置' : 'Save location';
  String get exportHint => isZh
      ? '提示：请在下载目录创建 databack 文件夹，并将文件移动到该文件夹中'
      : 'Hint: Please create a databack folder in the downloads directory and move the file there';
  String get backupFolderNotExists => isZh
      ? 'databack 文件夹不存在，请先导出数据创建该文件夹'
      : 'The databack folder does not exist. Please export data first to create it.';
  String get noBackupFiles =>
      isZh ? 'databack 文件夹中没有备份文件' : 'No backup files in the databack folder';

  // 备份恢复
  String get selectBackupFileTitle => isZh ? '选择备份文件' : 'Select Backup File';
  String get restoreFromAutoBackupTitle =>
      isZh ? '从自动备份恢复' : 'Restore from Auto Backup';
  String get backupTime => isZh ? '备份时间' : 'Backup time';
  String get taskCount => isZh ? '任务数量' : 'Task count';
  String get tagCount => isZh ? '标签数量' : 'Tag count';
  String get restoreConfirmHint => isZh
      ? '恢复将覆盖当前数据，确定要继续吗？'
      : 'Restoring will overwrite current data. Are you sure you want to continue?';
  String restoreSuccessCount(String tasks, String tags) => isZh
      ? '已恢复 $tasks 个任务和 $tags 个标签'
      : 'Restored $tasks tasks and $tags tags';
  String get restoreFailed =>
      isZh ? '恢复失败，请重试' : 'Restore failed, please try again';
  String get webOnlyFeature =>
      isZh ? '此功能仅支持Web版本' : 'This feature is only available in Web version';
  String get noAutoBackupData =>
      isZh ? '没有找到自动备份数据' : 'No auto backup data found';

  // 反馈
  String get feedbackContact => isZh
      ? '如有问题或建议，请联系：\nsupport@example.com'
      : 'For questions or suggestions, contact:\nsupport@example.com';

  // 隐私政策
  String get privacyPolicyContent => isZh
      ? '智能任务助手 隐私政策\n\n'
          '1. 我们重视您的隐私\n'
          '2. 所有数据仅存储在本地设备\n'
          '3. 我们不会收集或上传您的个人信息\n'
          '4. 您可以随时删除所有数据'
      : 'Smart Task Assistant Privacy Policy\n\n'
          '1. We value your privacy\n'
          '2. All data is stored locally on your device\n'
          '3. We do not collect or upload your personal information\n'
          '4. You can delete all data at any time';

  // AI配置
  String get apiKey => isZh ? 'API Key' : 'API Key';
  String get apiUrl => isZh ? 'API 地址' : 'API URL';
  String get modelName => isZh ? '模型名称' : 'Model Name';
  String get ollama => isZh ? 'Ollama（本地大模型）' : 'Ollama (Local LLM)';
  String get customApi => isZh ? '自定义 API' : 'Custom API';
  String get serviceMode => isZh ? '服务模式' : 'Service Mode';
  String get localRuleMode => isZh ? '本地规则模式' : 'Local Rule Mode';
  String get localRuleModeDesc => isZh
      ? '使用内置规则引擎，无需配置'
      : 'Use built-in rule engine, no configuration needed';
  String get localLLMMode => isZh ? '本地大模型模式' : 'Local LLM Mode';
  String get localLLMModeDesc =>
      isZh ? '使用本地部署的Ollama等大模型' : 'Use locally deployed LLM like Ollama';
  String get remoteAPIMode => isZh ? '远程API模式' : 'Remote API Mode';
  String get remoteAPIModeDesc =>
      isZh ? '使用OpenAI等在线API服务' : 'Use online API services like OpenAI';
  String get localLLMConfig => isZh ? '本地大模型配置' : 'Local LLM Config';
  String get serviceAddress => isZh ? '服务地址' : 'Service Address';
  String get localLLMHelp => isZh
      ? '请确保已安装Ollama并运行在指定地址'
      : 'Please make sure Ollama is installed and running at the specified address';
  String get remoteAPIConfig => isZh ? '远程API配置' : 'Remote API Config';
  String get apiServiceName => isZh ? 'API服务名称' : 'API Service Name';
  String get apiBase => isZh ? 'API基础地址' : 'API Base URL';
  String get apiModel => isZh ? 'API模型' : 'API Model';
  String get apiHelp =>
      isZh ? '请输入有效的API密钥和模型名称' : 'Please enter valid API key and model name';
  String get chatAIConfig => isZh ? '智答AI配置' : 'Chat AI Config';

  // 文件大小
  String get kb => isZh ? ' KB' : ' KB';

  // 错误提示
  String readBackupFolderError(String error) =>
      isZh ? '读取备份文件夹失败: $error' : 'Failed to read backup folder: $error';

  // 统计页面
  String get dataStatistics => isZh ? '数据统计' : 'Data Statistics';
  String get taskOverview => isZh ? '任务总览' : 'Task Overview';
  String get weeklyCompletionTrend =>
      isZh ? '本周完成趋势' : 'Weekly Completion Trend';
  String get priorityDistribution => isZh ? '优先级分布' : 'Priority Distribution';
  String get highPriority => isZh ? '高优先级' : 'High Priority';
  String get mediumPriority => isZh ? '中优先级' : 'Medium Priority';
  String get lowPriority => isZh ? '低优先级' : 'Low Priority';

  // 周期任务
  String get noRepeat => isZh ? '不重复' : 'No Repeat';
  String get dailyRepeat => isZh ? '每天' : 'Daily';
  String get weeklyRepeat => isZh ? '每周' : 'Weekly';
  String get monthlyRepeat => isZh ? '每月' : 'Monthly';
  String get yearlyRepeat => isZh ? '每年' : 'Yearly';

  // 任务卡片标签
  String get deleteTask => isZh ? '删除任务' : 'Delete Task';
  String get distributed => isZh ? '已分发' : 'Distributed';
  String get recurringCycleShort => isZh ? '周期' : 'Cycle';
  String reminderInAdvanceHours(int hours) =>
      isZh ? '提前$hours小时' : '$hours hr before';
  String reminderInAdvanceMinutes(int minutes) =>
      isZh ? '提前$minutes分钟' : '$minutes min before';

  // 提醒选项
  String get reminder5Min => isZh ? '5分钟前' : '5 min before';
  String get reminder15Min => isZh ? '15分钟前' : '15 min before';
  String get reminder30Min => isZh ? '30分钟前' : '30 min before';
  String get reminder1Hour => isZh ? '1小时前' : '1 hour before';
  String get reminder2Hour => isZh ? '2小时前' : '2 hours before';
  String get reminder1Day => isZh ? '1天前' : '1 day before';
  String get minutes10Before => isZh ? '10分钟前' : '10 min before';

  // 标签类型
  String get defaultTags => isZh ? '默认标签' : 'Default Tags';
  String get customTags => isZh ? '自定义标签' : 'Custom Tags';

  // AI模型名称
  String get deepSeek => isZh ? 'DeepSeek' : 'DeepSeek';
  String get qwen => isZh ? '通义千问' : 'Qwen';
  String get zhipuAI => isZh ? '智谱AI' : 'Zhipu AI';

  // 验证提示
  String get invalidDataFormat => isZh ? '无效的数据格式' : 'Invalid data format';
  String get restore => isZh ? '恢复' : 'Restore';

  // AI任务优先级建议
  String get aiAssistant => isZh ? 'AI 智能助手' : 'AI Assistant';
  String get analyzeTaskPriority => isZh ? '分析任务优先级' : 'Analyze Task Priority';
  String get efficiencyTips => isZh ? '效率建议' : 'Efficiency Tips';
  String get usageHelp => isZh ? '使用帮助' : 'Usage Help';
  String get aiSuggestionTitle => isZh ? 'AI 智能分析' : 'AI Analysis';
  String get smartSuggestionTitle => isZh ? '智能建议' : 'Smart Suggestion';
  String get recommendedOrder => isZh ? '推荐处理顺序' : 'Recommended Order';
  String get localRuleEngine => isZh ? '本地规则引擎' : 'Local Rule Engine';
  String get urgentTasksDetected => isZh ? '检测到紧急任务' : 'Urgent Tasks Detected';
  String get overdueTasksTitle => isZh ? '逾期任务' : 'Overdue Tasks';
  String get dueSoonTasks => isZh ? '即将到期' : 'Due Soon';
  String get moreTasks => isZh ? '还有' : '...还有';
  String get getPrioritySuggestion =>
      isZh ? '获取处理建议' : 'Get priority suggestions';
  String get noUrgentTasks =>
      isZh ? '太棒了！您目前没有未完成的任务。' : 'Great! You have no pending tasks.';
  String get overdueTasksCountSuggestion =>
      isZh ? '个逾期任务，建议优先处理。' : ' overdue tasks, suggest priority handling.';
  String get highPriorityTasksCountSuggestion =>
      isZh ? '个高优先级任务需要关注。' : ' high priority tasks need attention.';
  String get pendingTasksCountSuggestion => isZh
      ? '个未完成任务，建议合理安排时间。'
      : ' pending tasks, suggest reasonable time management.';

  // 习惯设置
  String get habitScheduleType =>
      isZh ? '提醒范围' : 'Reminder Range';
  String get habitScheduleTypeWeekdays =>
      isZh ? '工作日' : 'Weekdays';
  String get habitScheduleTypeDaily =>
      isZh ? '自然日' : 'Daily';
  String get habitScheduleTypeWeekdaysHint =>
      isZh ? '周一到周五' : 'Mon to Fri';
  String get habitScheduleTypeDailyHint =>
      isZh ? '每天' : 'Every day';

  // 全部任务页 - 筛选与批量
  String get allTags => isZh ? '全部标签' : 'All Tags';
  String get dateFrom => isZh ? '起始' : 'From';
  String get dateTo => isZh ? '截止' : 'To';
  String get batchMode => isZh ? '批量' : 'Batch';
  String get recentSearches => isZh ? '最近搜索' : 'Recent Searches';
  String get clear => isZh ? '清除' : 'Clear';
  String get clearDeadline => isZh ? '清除截止时间' : 'Clear Deadline';

  // 云同步状态
  String get syncNotLoggedIn => isZh ? '未登录云同步' : 'Not signed in to cloud sync';
  String get syncing => isZh ? '正在同步...' : 'Syncing...';
  String get syncFailedRetry => isZh ? '同步失败，点击重试' : 'Sync failed, tap to retry';
  String syncCompletedCount(int count) => isZh
      ? '同步完成，更新 $count 个任务'
      : 'Synced, $count task(s) updated';
  String syncFailedError(Object e) => isZh ? '同步失败：$e' : 'Sync failed: $e';
  String get syncEnabled => isZh ? '云同步已开启' : 'Cloud sync enabled';
  String lastSyncAt(String time) => isZh ? '最后同步 $time' : 'Last synced $time';

  // 任务评论
  String get taskComments => isZh ? '任务评论' : 'Task Comments';
  String get noComments => isZh ? '暂无评论' : 'No comments';
  String get addComment => isZh ? '添加评论' : 'Add Comment';
  String get commentHint => isZh ? '输入任务进展、说明或反馈' : 'Enter progress, notes or feedback';
  String get publish => isZh ? '发布' : 'Post';
  String commentFailed(Object e) => isZh ? '评论失败：$e' : 'Comment failed: $e';
  String get synced => isZh ? '已同步' : 'Synced';
  String get pendingSync => isZh ? '待同步' : 'Pending sync';
  String get syncFailedShort => isZh ? '同步失败' : 'Sync failed';
  String get syncFailedMultiline => isZh ? '同步\n失败' : 'Sync\nFailed';
  String get syncLabelOff => isZh ? '未登录' : 'Off';
  String get syncLabelSyncing => isZh ? '同步中' : 'Syncing';

  // 分发任务
  String get distributeToTeam => isZh ? '分发给团队成员' : 'Distribute to Team';
  String get distributeRemark => isZh ? '分发备注' : 'Remark';
  String get distributeRemarkHint => isZh ? '可选，例如处理要求或背景说明' : 'Optional, e.g. requirements or context';
  String get pleaseLoginBackend => isZh ? '请先在设置页登录后台同步' : 'Please sign in to backend sync in Settings first';
  String get notInAnyTeam => isZh ? '您尚未加入任何团队，请先在后台创建或加入团队' : 'You have not joined any team. Create or join one in the backend first.';
  String get noTeamMembers => isZh ? '暂无团队成员' : 'No team members';
  String distributeToMember(String name) => isZh ? '已分发给 $name' : 'Distributed to $name';
  String distributeFailed(Object e) => isZh ? '分发失败：$e' : 'Distribution failed: $e';
  String get distributionStatus => isZh ? '分发状态' : 'Distribution Status';

  // 分发状态枚举
  String get statusSent => isZh ? '已发送' : 'Sent';
  String get statusReceived => isZh ? '已接收' : 'Received';
  String get statusViewed => isZh ? '已查看' : 'Viewed';
  String get statusFailed => isZh ? '失败' : 'Failed';
  // 角色
  String get roleSender => isZh ? '发送方' : 'Sender';
  String get roleRecipient => isZh ? '接收方' : 'Recipient';
  String get roleAdmin => isZh ? '管理员' : 'Admin';

  // 状态变更日志 / 对方任务状态
  String get statusChangeLog => isZh ? '状态变更日志' : 'Status Change Log';
  String get noStatusChangeLogs => isZh ? '暂无状态变更记录' : 'No status change logs';
  String get unknown => isZh ? '未知' : 'Unknown';
  String get counterpart => isZh ? '对方' : 'Counterpart';
  String counterpartTaskStatus(String status) => isZh ? '对方任务状态：$status' : 'Counterpart task status: $status';
  String counterpartComments(String name) => isZh ? '$name的评论' : '$name\'s Comments';
  String commentsCount(int count) => isZh ? '$count条评论' : '$count comment(s)';
  String commentsCountWithSummary(int count, String summary) =>
      isZh ? '$count条评论：$summary' : '$count comment(s): $summary';
  String newCommentsCount(int count) => isZh ? '$count条新评论' : '$count new';

  // 通知中心
  String get notificationCenter => isZh ? '通知中心' : 'Notifications';
  String get markAllRead => isZh ? '全部已读' : 'Mark all read';
  String get noNotifications => isZh ? '暂无通知' : 'No notifications';

  // 任务指派
  String get assignedTo => isZh ? '指派给' : 'Assigned to';
  String get changeAssignee => isZh ? '更改指派' : 'Change assignee';
  String get assignTask => isZh ? '指派任务' : 'Assign Task';
  String get notInTeamCantAssign => isZh ? '未加入团队，无法指派' : 'Not in a team, cannot assign';
  String get self => isZh ? '（自己）' : '(me)';
  String get me => isZh ? '我' : 'Me';

  // 批量操作
  String selectedCount(int n) => isZh ? '已选 $n 项' : '$n selected';
  String get batchMarkComplete => isZh ? '标记完成' : 'Mark complete';
  String get batchStart => isZh ? '开始进行' : 'Start';
  String get batchDelete => isZh ? '批量删除' : 'Delete';
  String confirmBatchDelete(int n) => isZh ? '确定要删除选中的 $n 个任务吗？' : 'Delete $n selected task(s)?';

  // 周期任务
  String recurringTaskCompleted(String title) => isZh
      ? '周期任务「$title」已完成，已自动创建下一期'
      : 'Recurring task \"$title\" completed, next occurrence created';

  // AI 建议
  String get aiNoPendingTasks => isZh ? '🎉 今天没有待处理任务！' : '🎉 No pending tasks today!';
  String aiSuggestionPriority(String title) => isZh ? '💡 优先处理「$title」' : '💡 Priority: \"$title\"';
  String aiSuggestionNext(String title) => isZh ? '💡 建议处理「$title」' : '💡 Suggested: \"$title\"';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['zh', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// 简化的国际化扩展方法
extension LocalizationExtension on BuildContext {
  AppLocalizations get l =>
      AppLocalizations.of(this) ?? AppLocalizations(Locale('zh', 'CN'));
  bool get isZh => appSettings.isZh;
}
