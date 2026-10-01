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

  bool get isZh => true; // 纯中文版：已确立不做多语言，保留字段兼容既有调用

  // 通用
  String get appName => '智能任务助手';
  String get loading => '加载中...';
  String get confirm => '确认';
  String get cancel => '取消';
  String get save => '保存';
  String get delete => '删除';
  String get edit => '编辑';
  String get add => '添加';
  String get search => '搜索';
  String get searchHint => '搜索任务...';
  String get noData => '暂无数据';
  String get success => '成功';
  String get error => '错误';
  String get retry => '重试';
  String get loadFailed => '加载失败，请重试';
  String get close => '关闭';
  String get viewTask => '查看任务';

  // 底部导航
  String get navToday => '今天';
  String get navAll => '全部';
  String get navStats => '统计';
  String get navHabit => '习惯';
  String get navCalendar => '日历';
  String get navSettings => '设置';

  // 设置标签页
  String get chatAI => '智答AI';
  String get general => '通用';
  String get about => '关于';

  // 首页
  String get greetingMorning => '早上好';
  String get greetingNoon => '中午好';
  String get greetingAfternoon => '下午好';
  String get greetingEvening => '晚上好';
  String get greetingNight => '夜深了';
  String get overdueTasks => '逾期任务';
  String get pendingTasks => '未完成任务';
  String get viewAll => '查看全部';
  String get completed => '已完成';
  String get noTasks => '暂无任务';
  String get allTasksCompleted => '今日任务全部完成！';
  String completedTasksMsg(int count) => '已完成 $count 项任务，干得漂亮！';
  String get addTaskHint => '点击右下角按钮添加新任务';
  String get aiSuggestion => 'AI 智能建议';
  String get aiSuggestPriority => '建议优先处理';
  String get deadline => '截止时间';
  String get greatJob => '太棒了！今天没有待处理的任务，享受轻松时光吧！';

  // 任务状态
  String get statusPending => '待处理';
  String get statusInProgress => '进行中';
  String get statusCompleted => '已完成';
  String get statusCancelled => '已取消';

  // 优先级
  String get priorityHigh => '高优先级';
  String get priorityMedium => '中优先级';
  String get priorityLow => '低优先级';

  // 任务操作
  String get taskComplete => '任务已完成';
  String get taskDelete => '任务已删除';
  String get taskStart => '任务已开始';
  String get taskRestore => '任务已恢复';
  String get confirmDelete => '确认删除';
  String get confirmDeleteHint => '确定要删除这个任务吗？此操作不可撤销。';
  String get changeStatus => '修改状态';
  String get editTask => '编辑任务';
  String get addTask => '添加任务';
  String get taskTitle => '任务标题';
  String get taskContent => '任务内容';
  String get createTime => '创建时间';

  // 周期任务
  String get recurringTask => '周期任务';
  String get recurringTaskCompleteHint => '周期任务已完成，已自动创建下一期';

  // 设置页面
  String get settings => '设置';
  String get appearance => '外观';
  String get darkMode => '深色模式';
  String get darkModeHint => '切换深色/浅色主题';
  String get language => '语言';
  String get selectLanguage => '选择语言';
  String get notifications => '通知';
  String get pushNotifications => '推送通知';
  String get pushNotificationsHint => '接收任务提醒通知';
  String get clipboardMonitor => '剪贴板监视';
  String get clipboardMonitorHint => '粘贴内容时自动弹出任务创建窗口';
  String get aiService => 'AI 服务';
  String get aiServiceConfig => 'AI 服务配置';
  String get aiServiceConfigHint => '配置本地大模型或远程 API';
  String get tagManagement => '标签管理';
  String get addTag => '添加标签';
  String get tagName => '标签名称';
  String get editTag => '编辑标签';
  String get deleteTag => '删除标签';
  String get confirmDeleteTag => '确定要删除标签';
  String get dataManagement => '数据';
  String get exportData => '导出数据';
  String get importData => '导入数据';
  String get clearAllData => '清除所有数据';
  String get confirmClearData => '确定要删除所有任务和标签吗？此操作不可恢复。';
  String get dataCleared => '所有数据已清除';
  String get version => '版本';
  String get clearData => '清除数据';
  String get confirmClear => '确认清除';
  String get confirmClearHint => '确定要清除所有数据吗？此操作不可恢复。';
  String get clearSuccess => '清除成功';
  String get generalSettings => '通用设置';
  String get reminderSettings => '提醒设置';
  String get enableReminder => '启用提醒';
  String get reminderTime => '提醒时间';
  String get logViewer => '日志查看';
  String get viewLog => '查看日志';
  String get appDescription => '应用描述';
  String get appDescriptionText => '智能任务助手是一款基于AI的任务管理应用，帮助您高效管理日常任务。';
  String get features => '功能特性';
  String get feature1 => '智能任务识别';
  String get feature2 => 'AI智能建议';
  String get feature3 => '多种提醒方式';
  String get feature4 => '数据云端同步';
  String get contact => '联系我们';
  String get feedback => '反馈建议';
  String get feedbackHint => '帮助我们改进应用';
  String get privacyPolicy => '隐私政策';
  String get privacyPolicyHint => '查看隐私政策';

  // 导出导入
  String get exportSuccess => '已导出';
  String get importSuccess => '已导入';
  String get tasksAndTags => '个任务和';
  String get tags => '个标签';
  String get exportFailed => '导出失败';
  String get importFailed => '导入失败';
  String get noBackupFound => '没有找到备份文件';
  String get selectBackupFile => '选择备份文件';

  // AI 配置
  String get enableAI => '启用 AI 服务';
  String get enableAIHint => '关闭后将使用本地规则引擎';
  String get selectProvider => '选择服务商';
  String get localEngine => '本地规则引擎（无需配置）';
  String get testConnection => '测试连接';
  String get testing => '测试中...';
  String get connectionSuccess => '连接成功';
  String get connectionFailed => '连接失败';
  String get aiConfigSaved => 'AI 配置已保存';

  // 统计页面
  String get statistics => '统计';
  String get todayProgress => '今日进度';
  String get weeklyOverview => '本周概览';
  String get taskDistribution => '任务分布';
  String get completionRate => '完成率';
  String get totalTasks => '总任务';
  String get completedTasks => '已完成';
  String get inProgressTasks => '进行中';
  String get pendingTasksCount => '待处理';
  String get overdueTasksCount => '已逾期';

  // 快速添加
  String get quickAddTask => '快速添加任务';
  String get taskTitleHint => '输入任务标题...';
  String get selectDueTime => '选择截止时间';
  String get selectPriority => '选择优先级';
  String get today => '今天';
  String get tomorrow => '明天';
  String get thisWeek => '本周';
  String get nextWeek => '下周';
  String get noDeadline => '无截止时间';
  String get customTime => '自定义时间';

  // 日期
  String get monday => '周一';
  String get tuesday => '周二';
  String get wednesday => '周三';
  String get thursday => '周四';
  String get friday => '周五';
  String get saturday => '周六';
  String get sunday => '周日';

  // 时间相关
  String get daysAgo => '天前';
  String get hoursAgo => '小时前';
  String get minutesAgo => '分钟前';
  String get justNow => '刚刚';
  String get later => '后';
  String get overdue => '已逾期';

  // 筛选
  String get filterAll => '全部';
  String get filterOverdue => '已逾期';

  // 通知
  String get overdueReminder => '逾期任务提醒';
  String get noOverdueTasks => '暂无逾期任务';
  String get view => '查看';

  // 添加/编辑任务页面
  String get newTask => '新建任务';
  String get taskDetails => '任务详情';
  String get enterTaskTitle => '输入任务标题...';
  String get enterTaskDetails => '输入任务详情...';
  String get selectDeadline => '选择截止时间';
  String get noReminder => '不提醒';
  String get minBefore => '分钟前';
  String get hourBefore => '1小时前';
  String get custom => '自定义';
  String get enterMinutes => '输入分钟数';
  String get priority => '优先级';
  String get priorityLowShort => '低';
  String get priorityMediumShort => '中';
  String get priorityHighShort => '高';
  String get tagsLabel => '标签';
  String get recurringTaskSettings => '周期任务';
  String get setAsRecurring => '设为周期任务';
  String get autoCreateNext => '完成后自动创建新任务';
  String get off => '关闭';
  String get repeatCycle => '重复周期';
  String get daily => '每天';
  String get weekly => '每周';
  String get monthly => '每月';
  String get taskStatus => '任务状态';
  String get inProgress => '进行中';
  String get aiDetected => 'AI 智能识别';
  String get timeKeywordDetected => '检测到时间关键词，建议设置截止时间';
  String get priorityKeywordDetected => '检测到优先级关键词，建议设为高优先级';
  String get pleaseEnterTitle => '请输入任务标题';
  String get taskUpdated => '任务已更新';
  String get reminder => '提醒';

  // 标签默认值
  String get tagWork => '工作';
  String get tagPersonal => '个人';
  String get tagUrgent => '紧急';
  String get tagStudy => '学习';
  String get defaultTag => '默认';

  // 数据导出导入
  String get exportedCount => '✓ 已导出';
  String get importedCount => '已导入';
  String get saveLocation => '保存位置';
  String get exportHint => '提示：请在下载目录创建 databack 文件夹，并将文件移动到该文件夹中';
  String get backupFolderNotExists => 'databack 文件夹不存在，请先导出数据创建该文件夹';
  String get noBackupFiles => 'databack 文件夹中没有备份文件';

  // 备份恢复
  String get selectBackupFileTitle => '选择备份文件';
  String get restoreFromAutoBackupTitle => '从自动备份恢复';
  String get backupTime => '备份时间';
  String get taskCount => '任务数量';
  String get tagCount => '标签数量';
  String get restoreConfirmHint => '恢复将覆盖当前数据，确定要继续吗？';
  String restoreSuccessCount(String tasks, String tags) => '已恢复 $tasks 个任务和 $tags 个标签';
  String get restoreFailed => '恢复失败，请重试';
  String get webOnlyFeature => '此功能仅支持Web版本';
  String get noAutoBackupData => '没有找到自动备份数据';

  // 反馈
  String get feedbackContact => '如有问题或建议，请联系：\nsupport@example.com';

  // 隐私政策
  String get privacyPolicyContent => '智能任务助手 隐私政策\n\n'
          '1. 我们重视您的隐私\n'
          '2. 所有数据仅存储在本地设备\n'
          '3. 我们不会收集或上传您的个人信息\n'
          '4. 您可以随时删除所有数据';

  // AI配置
  String get apiKey => 'API Key';
  String get apiUrl => 'API 地址';
  String get modelName => '模型名称';
  String get ollama => 'Ollama（本地大模型）';
  String get customApi => '自定义 API';
  String get serviceMode => '服务模式';
  String get localRuleMode => '本地规则模式';
  String get localRuleModeDesc => '使用内置规则引擎，无需配置';
  String get localLLMMode => '本地大模型模式';
  String get localLLMModeDesc => '使用本地部署的Ollama等大模型';
  String get remoteAPIMode => '远程API模式';
  String get remoteAPIModeDesc => '使用OpenAI等在线API服务';
  String get localLLMConfig => '本地大模型配置';
  String get serviceAddress => '服务地址';
  String get localLLMHelp => '请确保已安装Ollama并运行在指定地址';
  String get remoteAPIConfig => '远程API配置';
  String get apiServiceName => 'API服务名称';
  String get apiBase => 'API基础地址';
  String get apiModel => 'API模型';
  String get apiHelp => '请输入有效的API密钥和模型名称';
  String get chatAIConfig => '智答AI配置';

  // 文件大小
  String get kb => ' KB';

  // 错误提示
  String readBackupFolderError(String error) => '读取备份文件夹失败: $error';

  // 统计页面
  String get dataStatistics => '数据统计';
  String get taskOverview => '任务总览';
  String get weeklyCompletionTrend => '本周完成趋势';
  String get priorityDistribution => '优先级分布';
  String get highPriority => '高优先级';
  String get mediumPriority => '中优先级';
  String get lowPriority => '低优先级';

  // 周期任务
  String get noRepeat => '不重复';
  String get dailyRepeat => '每天';
  String get weeklyRepeat => '每周';
  String get monthlyRepeat => '每月';
  String get yearlyRepeat => '每年';

  // 任务卡片标签
  String get deleteTask => '删除任务';
  String get distributed => '已分发';
  String get recurringCycleShort => '周期';
  String reminderInAdvanceHours(int hours) => '提前$hours小时';
  String reminderInAdvanceMinutes(int minutes) => '提前$minutes分钟';

  // 提醒选项
  String get reminder5Min => '5分钟前';
  String get reminder15Min => '15分钟前';
  String get reminder30Min => '30分钟前';
  String get reminder1Hour => '1小时前';
  String get reminder2Hour => '2小时前';
  String get reminder1Day => '1天前';
  String get minutes10Before => '10分钟前';

  // 标签类型
  String get defaultTags => '默认标签';
  String get customTags => '自定义标签';

  // AI模型名称
  String get deepSeek => 'DeepSeek';
  String get qwen => '通义千问';
  String get zhipuAI => '智谱AI';

  // 验证提示
  String get invalidDataFormat => '无效的数据格式';
  String get restore => '恢复';

  // AI任务优先级建议
  String get aiAssistant => 'AI 智能助手';
  String get analyzeTaskPriority => '分析任务优先级';
  String get efficiencyTips => '效率建议';
  String get usageHelp => '使用帮助';
  String get aiSuggestionTitle => 'AI 智能分析';
  String get smartSuggestionTitle => '智能建议';
  String get recommendedOrder => '推荐处理顺序';
  String get localRuleEngine => '本地规则引擎';
  String get urgentTasksDetected => '检测到紧急任务';
  String get overdueTasksTitle => '逾期任务';
  String get dueSoonTasks => '即将到期';
  String get moreTasks => '还有';
  String get getPrioritySuggestion => '获取处理建议';
  String get noUrgentTasks => '太棒了！您目前没有未完成的任务。';
  String get overdueTasksCountSuggestion => '个逾期任务，建议优先处理。';
  String get highPriorityTasksCountSuggestion => '个高优先级任务需要关注。';
  String get pendingTasksCountSuggestion => '个未完成任务，建议合理安排时间。';

  // 习惯设置
  String get habitScheduleType => '提醒范围';
  String get habitScheduleTypeWeekdays => '工作日';
  String get habitScheduleTypeDaily => '自然日';
  String get habitScheduleTypeWeekdaysHint => '周一到周五';
  String get habitScheduleTypeDailyHint => '每天';

  // 全部任务页 - 筛选与批量
  String get allTags => '全部标签';
  String get dateFrom => '起始';
  String get dateTo => '截止';
  String get batchMode => '批量';
  String get recentSearches => '最近搜索';
  String get clear => '清除';
  String get clearDeadline => '清除截止时间';

  // 云同步状态
  String get syncNotLoggedIn => '未登录云同步';
  String get syncing => '正在同步...';
  String get syncFailedRetry => '同步失败，点击重试';
  String syncCompletedCount(int count) => '同步完成，更新 $count 个任务';
  String syncFailedError(Object e) => '同步失败：$e';
  String get syncEnabled => '云同步已开启';
  String lastSyncAt(String time) => '最后同步 $time';

  // 任务评论
  String get taskComments => '任务评论';
  String get noComments => '暂无评论';
  String get addComment => '添加评论';
  String get commentHint => '输入任务进展、说明或反馈';
  String get publish => '发布';
  String commentFailed(Object e) => '评论失败：$e';
  String get synced => '已同步';
  String get pendingSync => '待同步';
  String get syncFailedShort => '同步失败';
  String get syncFailedMultiline => '同步\n失败';
  String get syncLabelOff => '未登录';
  String get syncLabelSyncing => '同步中';

  // 分发任务
  String get distributeToTeam => '分发给团队成员';
  String get distributeRemark => '分发备注';
  String get distributeRemarkHint => '可选，例如处理要求或背景说明';
  String get pleaseLoginBackend => '请先在设置页登录后台同步';
  String get notInAnyTeam => '您尚未加入任何团队，请先在后台创建或加入团队';
  String get noTeamMembers => '暂无团队成员';
  String distributeToMember(String name) => '已分发给 $name';
  String distributeFailed(Object e) => '分发失败：$e';
  String get distributionStatus => '分发状态';

  // 分发状态枚举
  String get statusSent => '已发送';
  String get statusReceived => '已接收';
  String get statusViewed => '已查看';
  String get statusFailed => '失败';
  // 角色
  String get roleSender => '发送方';
  String get roleRecipient => '接收方';
  String get roleAdmin => '管理员';

  // 状态变更日志 / 对方任务状态
  String get statusChangeLog => '状态变更日志';
  String get noStatusChangeLogs => '暂无状态变更记录';
  String get unknown => '未知';
  String get counterpart => '对方';
  String counterpartTaskStatus(String status) => '对方任务状态：$status';
  String counterpartComments(String name) => '$name的评论';
  String commentsCount(int count) => '$count条评论';
  String commentsCountWithSummary(int count, String summary) => '$count条评论：$summary';
  String newCommentsCount(int count) => '$count条新评论';

  // 通知中心
  String get notificationCenter => '通知中心';
  String get markAllRead => '全部已读';
  String get noNotifications => '暂无通知';

  // 任务指派
  String get assignedTo => '指派给';
  String get changeAssignee => '更改指派';
  String get assignTask => '指派任务';
  String get notInTeamCantAssign => '未加入团队，无法指派';
  String get self => '（自己）';
  String get me => '我';

  // 批量操作
  String selectedCount(int n) => '已选 $n 项';
  String get batchMarkComplete => '标记完成';
  String get batchStart => '开始进行';
  String get batchDelete => '批量删除';
  String confirmBatchDelete(int n) => '确定要删除选中的 $n 个任务吗？';

  // 滑动操作（任务卡片）
  String get swipeComplete => '完成';
  String get swipeUndoComplete => '恢复';
  String get swipeStart => '开始';
  String get swipeDelete => '删除';

  // 撤销操作
  String get undo => '撤销';
  String taskCompletedUndo(String title) => '已完成「$title」';
  String get undoDelete => '恢复删除';
  String get taskDeletedUndo => '任务已删除';

  // 任务模板
  String get saveAsTemplate => '保存为模板';
  String get savedAsTemplate => '已保存为模板';
  String get templates => '任务模板';

  // 完成趋势
  String completedThisWeek(int n) => '本周完成 $n 个';
  String moreThanLastWeek(int n) => '较上周 +$n';
  String lessThanLastWeek(int n) => '较上周 $n';
  String get sameAsLastWeek => '与上周持平';

  // 周期任务
  String recurringTaskCompleted(String title) => '周期任务「$title」已完成，已自动创建下一期';

  // AI 建议
  String get aiNoPendingTasks => '🎉 今天没有待处理任务！';
  String aiSuggestionPriority(String title) => '💡 优先处理「$title」';
  String aiSuggestionNext(String title) => '💡 建议处理「$title」';
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
      AppLocalizations.of(this) ?? AppLocalizations(const Locale('zh', 'CN'));
  bool get isZh => true; // 纯中文版：已确立不做多语言
}
