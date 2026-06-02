import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../models/task_comment.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';
import '../widgets/quick_add_modal.dart';
import '../widgets/ai_chat_dialog.dart';
import '../utils/app_localizations.dart';
import '../services/weather_service.dart';
import '../models/city.dart';
import '../widgets/city_selector_dialog.dart';
import '../services/backend_api_service.dart';
import '../services/task_comment_service.dart';
import 'add_task_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'habit_screen.dart';
import 'calendar_screen.dart';
import '../widgets/distribution_status_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/subtask_list.dart';
import '../widgets/activity_feed_dialog.dart';

/// 主页面 - 互联网风格设计
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  String? _selectedFilter;
  String? _selectedTagId; // 标签筛选，null=全部
  bool _isBatchMode = false;
  final Set<String> _selectedTaskIds = {};
  late AnimationController _fabAnimationController;
  bool _isCompletedExpanded = false; // 已完成任务栏目展开状态
  int _unreadNotificationCount = 0;
  bool _isAICardDismissed = false; // AI 建议卡片是否已关闭

  // Cached futures for FutureBuilders (prevents rebuild from re-triggering)
  final Map<String, Future<List<TaskComment>>> _commentsFutureCache = {};
  final Map<String, Future<List<BackendDistribution>>> _distributionsFutureCache = {};
  final Map<String, Future<List<BackendTaskComment>>> _recipientCommentsFutureCache = {};

  // 时间和天气相关
  Timer? _timeTimer;
  final ValueNotifier<String> _currentTimeNotifier = ValueNotifier('');
  static final WeatherService _weatherService = WeatherService();
  WeatherInfo? _weatherInfo;
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 初始化时间
    _updateTime();
    _timeTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _updateTime());

    // 强制刷新天气信息（不使用缓存，以获取最新位置）
    _forceRefreshWeather();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _timeTimer?.cancel();
    _currentTimeNotifier.dispose();
    super.dispose();
  }

  /// 更新时间
  void _updateTime() {
    final now = DateTime.now();
    _currentTimeNotifier.value =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  /// 强制刷新天气
  Future<void> _forceRefreshWeather() async {
    if (_isLoadingWeather) {
      return;
    }

    setState(() {
      _isLoadingWeather = true;
    });

    try {
      final weather = await _weatherService.refreshWeather();
      setState(() {
        _weatherInfo = weather;
        _isLoadingWeather = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingWeather = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppTheme.backgroundColor,
        child: SafeArea(
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildTodayPage();
      case 1:
        return _buildAllTasksPage();
      case 2:
        return const HabitScreen();
      case 3:
        return const CalendarScreen();
      case 4:
        return StatsScreen(
          onNavigateToAllTasks: () => setState(() => _currentIndex = 1),
          onNavigateToFiltered: (filter) {
            setState(() {
              _currentIndex = 1;
              if (filter == 'overdue') {
                _selectedFilter = 'overdue';
                context.read<TaskProvider>().setFilterStatus(null);
              }
            });
          },
        );
      case 5:
        return const SettingsScreen();
      default:
        return _buildTodayPage();
    }
  }

  /// 今日任务页面 - 互联网风格
  Widget _buildTodayPage() {
    return Consumer<TaskProvider>(
      builder: (context, provider, child) {
        final l = context.l;
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryColor),
          );
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 顶部标题区域
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部工具栏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              // 天气紧凑图标
                              _buildWeatherChip(),
                              const SizedBox(width: 8),
                              // 云同步状态点
                              _buildSyncDot(provider),
                              const SizedBox(width: 8),
                              // 离线提示点
                              StreamBuilder<List<ConnectivityResult>>(
                                stream: Connectivity().onConnectivityChanged,
                                initialData: const [ConnectivityResult.wifi],
                                builder: (context, snapshot) {
                                  final results = snapshot.data ?? [ConnectivityResult.wifi];
                                  final isOffline = results.contains(ConnectivityResult.none);
                                  if (!isOffline) return const SizedBox.shrink();
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _buildHeaderButton(
                              Icons.search_rounded,
                              () => setState(() => _currentIndex = 1),
                            ),
                            const SizedBox(width: 8),
                            _buildHeaderButton(
                              Icons.timeline_rounded,
                              () => _showActivityFeed(),
                            ),
                            const SizedBox(width: 8),
                            _buildHeaderButton(
                              Icons.notifications_none_rounded,
                              () => _showNotificationCenter(),
                              badge: _unreadNotificationCount > 0
                                  ? '$_unreadNotificationCount'
                                  : (provider.overdueTasks.isNotEmpty
                                      ? '${provider.overdueTasks.length}'
                                      : null),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 进度卡片 - 紧凑版
                    _buildProgressCard(provider),
                  ],
                ),
              ),
            ),
            // AI 建议卡片
            if (provider.todayTasks.any((t) => !t.isCompleted) && !_isAICardDismissed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildAISuggestionCard(provider),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),
            // 逾期任务标签（仅有逾期时显示）
            if (provider.overdueTasks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.errorColor,
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${l.overdueTasks} (${provider.overdueTasks.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 待处理任务列表 - 逾期任务排前面，然后是今日任务
            provider.todayTasks.every((t) => t.isCompleted) && provider.overdueTasks.isEmpty
                ? SliverToBoxAdapter(
                    child: provider.todayTasks.isEmpty
                        ? _buildEmptyState()
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 32),
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
                                Icon(Icons.emoji_events_rounded,
                                    size: 56,
                                    color: AppTheme.primaryColor.withValues(alpha: 0.6)),
                                const SizedBox(height: 12),
                                Text(
                                  l.allTasksCompleted,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l.completedTasksMsg(
                                      provider.todayTasks.length),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textHintColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  )
                : Builder(builder: (context) {
                    // 逾期任务（未完成的）排最前
                    final overdueUncompleted = provider.overdueTasks
                        .where((t) => !t.isCompleted)
                        .toList();
                    // 今日未完成任务
                    final todayUncompleted = provider.todayTasks
                        .where((t) => !t.isCompleted)
                        .toList();
                    // 合并：逾期 + 今日（去重）
                    final overdueIds = overdueUncompleted.map((t) => t.id).toSet();
                    final mergedTasks = [
                      ...overdueUncompleted,
                      ...todayUncompleted.where((t) => !overdueIds.contains(t.id)),
                    ];
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = mergedTasks[index];
                            final isOverdue = overdueIds.contains(task.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                decoration: isOverdue
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppTheme.errorColor.withValues(alpha: 0.4),
                                          width: 1.5,
                                        ),
                                      )
                                    : null,
                                child: TaskCard(
                                  task: task,
                                  onTap: () => _showTaskDetail(task),
                                  isDistributed: provider.distributedTaskIds.contains(task.id),
                                  onComplete: () =>
                                      _completeTask(task.id, provider),
                                  onDelete: () => _deleteTask(task.id, provider),
                                  onStart: () => _startTask(task.id, provider),
                                  onStatusChange: (status) =>
                                      _changeTaskStatus(task.id, status, provider),
                                  onPriorityChange: (priority) =>
                                      _changeTaskPriority(
                                          task.id, priority, provider),
                                  onDueTimeTap: () => _editDueTime(task, provider),
                                  onReminderTap: () =>
                                      _editReminder(task, provider),
                                  onRecurringTap: () =>
                                      _editRecurring(task, provider),
                                  availableTags: _getAllTags(provider),
                                  onTagsChanged: (tagIds) =>
                                      _updateTaskTags(task.id, tagIds, provider),
                                ),
                              ),
                            );
                          },
                          childCount: mergedTasks.length,
                        ),
                      ),
                    );
                  }),
            // 已完成任务分组（从全部任务中获取已完成任务，不受 todayTasks 过滤限制）
            if (provider.completedTasks.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildCompletedSection(provider),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        );
      },
    );
  }

  /// 所有任务页面
  Widget _buildAllTasksPage() {
    return Consumer<TaskProvider>(
      builder: (context, provider, child) {
        final l = context.l;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.navAll,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: provider.setSearchQuery,
                                onSubmitted: provider.setSearchQuery,
                                decoration: InputDecoration(
                                  hintText: l.searchHint,
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            if (provider.searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () => provider.setSearchQuery(''),
                              ),
                            Container(
                              margin: const EdgeInsets.all(4),
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  FocusScope.of(context).unfocus();
                                },
                                icon: const Icon(Icons.search, size: 18),
                                label: Text(l.search),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(l.filterAll, null, provider),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                                l.statusPending, TaskStatus.pending, provider),
                            const SizedBox(width: 8),
                            _buildFilterChip(l.statusInProgress,
                                TaskStatus.inProgress, provider),
                            const SizedBox(width: 8),
                            _buildFilterChip(l.statusCompleted,
                                TaskStatus.completed, provider),
                            const SizedBox(width: 8),
                            _buildFilterChip(l.filterOverdue, null, provider,
                                isOverdue: true),
                          ],
                        ),
                      ),
                      // 标签筛选
                      Consumer<TaskProvider>(
                        builder: (context, provider, _) {
                          final tags = _getAllTags(provider);
                          if (tags.isEmpty) return const SizedBox.shrink();
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildTagFilterChip(null, '全部标签', null),
                                const SizedBox(width: 8),
                                ...tags.map((tag) => Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _buildTagFilterChip(
                                          tag.id, tag.name, tag.color),
                                    )),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Date range filter + batch mode toggle
                      Row(
                        children: [
                          _buildDateRangeChip('起始', provider.filterDateFrom, (dt) {
                            provider.setFilterDateRange(dt, provider.filterDateTo);
                          }),
                          const SizedBox(width: 8),
                          _buildDateRangeChip('截止', provider.filterDateTo, (dt) {
                            provider.setFilterDateRange(provider.filterDateFrom, dt);
                          }),
                          if (provider.filterDateFrom != null || provider.filterDateTo != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: GestureDetector(
                                onTap: () => provider.setFilterDateRange(null, null),
                                child: Icon(Icons.clear, size: 16, color: Colors.grey[400]),
                              ),
                            ),
                          const Spacer(),
                          // Recent searches
                          if (provider.recentSearches.isNotEmpty && provider.searchQuery.isEmpty)
                            GestureDetector(
                              onTap: () => _showRecentSearches(provider),
                              child: Icon(Icons.history, size: 20, color: Colors.grey[400]),
                            ),
                          const SizedBox(width: 8),
                          // Batch mode toggle
                          GestureDetector(
                            onTap: () => setState(() {
                              _isBatchMode = !_isBatchMode;
                              if (!_isBatchMode) _selectedTaskIds.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isBatchMode ? AppTheme.primaryColor : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.checklist, size: 16,
                                    color: _isBatchMode ? Colors.white : Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text('批量',
                                    style: TextStyle(fontSize: 12,
                                      color: _isBatchMode ? Colors.white : Colors.grey[600])),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              // Batch mode toolbar
              if (_isBatchMode)
                SliverToBoxAdapter(
                  child: _buildBatchToolbar(provider),
                ),
              _getFilteredTaskList(provider).isEmpty
                  ? SliverToBoxAdapter(
                      child: _buildEmptyState(isWhite: true),
                    )
                  : Builder(builder: (context) {
                      final filteredTasks = _getFilteredTaskList(provider);
                      return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = filteredTasks[index];
                            if (task.parentId != null) return const SizedBox.shrink();
                            final subtasks = provider.subtasksByParentId[task.id] ?? [];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TaskCard(
                                    task: task,
                                    onTap: _isBatchMode
                                        ? () => setState(() {
                                              if (_selectedTaskIds.contains(task.id)) {
                                                _selectedTaskIds.remove(task.id);
                                              } else {
                                                _selectedTaskIds.add(task.id);
                                              }
                                            })
                                        : () => _showTaskDetail(task),
                                    isDistributed: provider.distributedTaskIds.contains(task.id),
                                    isPinned: provider.isPinned(task.id),
                                    onPinToggle: () => provider.isPinned(task.id)
                                        ? provider.unpinTask(task.id)
                                        : provider.pinTask(task.id),
                                    selectable: _isBatchMode,
                                    isSelected: _selectedTaskIds.contains(task.id),
                                    onSelectionChanged: (v) => setState(() {
                                      if (v) {
                                        _selectedTaskIds.add(task.id);
                                      } else {
                                        _selectedTaskIds.remove(task.id);
                                      }
                                    }),
                                    onComplete: () => _completeTask(task.id, provider),
                                    onDelete: () => _deleteTask(task.id, provider),
                                    onStart: () => _startTask(task.id, provider),
                                    onStatusChange: (status) => _changeTaskStatus(task.id, status, provider),
                                    onPriorityChange: (priority) => _changeTaskPriority(task.id, priority, provider),
                                    onDueTimeTap: () => _editDueTime(task, provider),
                                    onReminderTap: () => _editReminder(task, provider),
                                    onRecurringTap: () => _editRecurring(task, provider),
                                    availableTags: _getAllTags(provider),
                                    onTagsChanged: (tagIds) => _updateTaskTags(task.id, tagIds, provider),
                                  ),
                                ),
                                if (subtasks.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SubtaskList(
                                      parentTask: task,
                                      subtasks: subtasks,
                                      onSubtaskTap: (t) => _showTaskDetail(t),
                                      onAddSubtask: () {
                                        Navigator.push(context, MaterialPageRoute(
                                          builder: (_) => AddTaskScreen(parentId: task.id),
                                        ));
                                      },
                                    ),
                                  ),
                              ],
                            );
                          },
                          childCount: filteredTasks.length,
                        ),
                      ),
                    );
                  }),
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderButton(IconData icon, VoidCallback onTap,
      {String? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, color: AppTheme.textSecondaryColor, size: 22),
            ),
            if (badge != null)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 天气紧凑图标（顶栏用）
  Widget _buildWeatherChip() {
    return GestureDetector(
      onTap: _showCitySelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getWeatherIcon(),
              size: 16,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              _weatherInfo?.temperatureText ?? '--°C',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
            if (_weatherInfo?.cityName != null) ...[
              const SizedBox(width: 3),
              Text(
                _weatherInfo!.cityName!,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textHintColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 云同步状态点（顶栏用）
  Widget _buildSyncDot(TaskProvider provider) {
    final loggedIn = provider.isBackendLoggedIn;
    Color dotColor;
    String tooltip;
    VoidCallback onTap;

    if (!loggedIn) {
      dotColor = AppTheme.textHintColor;
      tooltip = '未登录云同步';
      onTap = () => setState(() => _currentIndex = 5);
    } else if (provider.isBackendSyncing) {
      dotColor = AppTheme.infoColor;
      tooltip = '正在同步...';
      onTap = () {};
    } else if (provider.backendSyncError != null && provider.backendSyncError!.isNotEmpty) {
      dotColor = AppTheme.errorColor;
      tooltip = '同步失败，点击重试';
      onTap = () async {
        try {
          final count = await provider.syncAllWithBackend();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步完成，更新 $count 个任务')),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步失败：$e')),
          );
        }
      };
    } else {
      dotColor = AppTheme.successColor;
      tooltip = provider.lastBackendSyncAt == null
          ? '云同步已开启'
          : '最后同步 ${_formatDateTime(provider.lastBackendSyncAt!)}';
      onTap = () async {
        try {
          final count = await provider.syncAllWithBackend();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步完成，更新 $count 个任务')),
          );
        } catch (_) {}
      };
    }

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      String label, TaskStatus? status, TaskProvider provider,
      {bool isOverdue = false}) {
    final isSelected = isOverdue
        ? _selectedFilter == 'overdue'
        : provider.filterStatus == status && _selectedFilter != 'overdue';

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isOverdue) {
            _selectedFilter = 'overdue';
            provider.setFilterStatus(null);
          } else {
            _selectedFilter = null;
            provider.setFilterStatus(status);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? AppTheme.primaryColor : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : AppTheme.textSecondaryColor,
          ),
        ),
      ),
    );
  }

  /// 标签筛选芯片
  Widget _buildTagFilterChip(String? tagId, String label, String? colorHex) {
    final isSelected = _selectedTagId == tagId;
    Color? tagColor;
    if (colorHex != null) {
      try {
        tagColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      } catch (_) {
        tagColor = Colors.grey;
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTagId = tagId;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (tagColor ?? AppTheme.primaryColor)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (tagColor ?? AppTheme.primaryColor)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tagColor != null && !isSelected) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: tagColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.white : AppTheme.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({bool isWhite = false}) {
    final l = context.l;
    return EmptyStateWidget(
      icon: Icons.task_alt_rounded,
      title: l.noTasks,
      subtitle: l.addTaskHint,
    );
  }

  Widget _buildBottomNav() {
    final l = context.l;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _buildNavItem(0, Icons.today_rounded, l.navToday),
              _buildNavItem(1, Icons.list_rounded, l.navAll),
              _buildNavItem(2, Icons.event_repeat_rounded, '习惯'),
              _buildNavItem(3, Icons.calendar_month_rounded, '日历'),
              _buildNavItem(4, Icons.bar_chart_rounded, l.navStats),
              _buildNavItem(5, Icons.settings_rounded, l.navSettings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        if (_currentIndex != index) {
          _selectedFilter = null;
          _selectedTagId = null;
        }
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color:
                  isSelected ? AppTheme.primaryColor : AppTheme.textHintColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color:
                    isSelected ? AppTheme.primaryColor : AppTheme.textHintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => showQuickAddModal(context),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add_rounded, size: 32, color: Colors.white),
      ),
    );
  }

  /// 显示城市选择对话框
  Future<void> _showCitySelector() async {
    final selectedCity = await showDialog<CityInfo>(
      context: context,
      builder: (context) => CitySelectorDialog(
        initialSelectedCity: _weatherService.selectedCity,
      ),
    );

    if (selectedCity != null) {
      setState(() {
        _isLoadingWeather = true;
      });

      // setSelectedCity内部会自动调用getWeather(forceRefresh: true)
      // 它会返回获取到的天气数据
      final weather = await _weatherService.setSelectedCity(selectedCity);

      if (mounted) {
        setState(() {
          _weatherInfo = weather;
          _isLoadingWeather = false;
        });
      }
    }
  }

  /// 根据天气描述获取图标
  IconData _getWeatherIcon() {
    if (_weatherInfo == null) return Icons.cloud_rounded;

    final description = _weatherInfo!.description.toLowerCase();
    if (description.contains('rain') || description.contains('雨')) {
      return Icons.water_drop_rounded;
    } else if (description.contains('cloud') ||
        description.contains('云') ||
        description.contains('阴')) {
      return Icons.cloud_rounded;
    } else if (description.contains('sun') || description.contains('晴')) {
      return Icons.wb_sunny_rounded;
    } else if (description.contains('snow') || description.contains('雪')) {
      return Icons.ac_unit_rounded;
    } else if (description.contains('thunder') || description.contains('雷')) {
      return Icons.flash_on_rounded;
    } else if (description.contains('fog') || description.contains('雾')) {
      return Icons.cloud_queue_rounded;
    } else {
      return Icons.wb_sunny_rounded;
    }
  }

  /// 构建进度卡片 - 紧凑版
  Widget _buildProgressCard(TaskProvider provider) {
    final l = context.l;
    final allTasks = provider.tasks;
    final overdueTasks = provider.overdueTasks;

    // 已完成计数从全部任务获取，确保与已完成卡片一致
    final completedCount = provider.completedTasks.length;
    final inProgressTasks = allTasks
        .where((t) =>
            t.status == TaskStatus.inProgress && !t.isCompleted && !t.isOverdue)
        .toList();
    final pendingTasks = allTasks
        .where((t) =>
            t.status == TaskStatus.pending && !t.isCompleted && !t.isOverdue)
        .toList();

    final inProgressCount = inProgressTasks.length;
    final pendingCount = pendingTasks.length;
    final overdueCount = overdueTasks.length;
    final totalCount = allTasks.length;
    final activeTotal =
        completedCount + inProgressCount + pendingCount + overdueCount;
    final progressPercent =
        activeTotal > 0 ? completedCount / activeTotal : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 紧凑的进度环
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progressPercent,
                    strokeWidth: 6,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(progressPercent * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      '$completedCount/$totalCount',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 紧凑的统计信息 - 横向排列
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCompactStatItem(
                    l.completedTasks, completedCount, AppTheme.successColor),
                _buildCompactStatItem(
                    l.inProgressTasks, inProgressCount, AppTheme.warningColor),
                _buildCompactStatItem(
                    l.pendingTasksCount, pendingCount, AppTheme.infoColor),
                if (overdueCount > 0)
                  _buildCompactStatItem(
                      l.overdueTasksCount, overdueCount, AppTheme.errorColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑的统计项
  Widget _buildCompactStatItem(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  /// 构建AI建议卡片 - 紧凑单行横幅
  Widget _buildAISuggestionCard(TaskProvider provider) {
    final uncompletedTasks =
        provider.todayTasks.where((t) => !t.isCompleted).toList();
    final highPriorityTasks =
        uncompletedTasks.where((t) => t.priority == TaskPriority.high).toList();
    final highPriorityTask =
        highPriorityTasks.isNotEmpty ? highPriorityTasks.first : null;

    String suggestion = '🎉 今天没有待处理任务！';
    if (highPriorityTask != null) {
      suggestion = '💡 优先处理「${highPriorityTask.title}」';
      if (highPriorityTask.dueTime != null) {
        suggestion += ' · ${highPriorityTask.dueTimeDescription}';
      }
    } else if (uncompletedTasks.isNotEmpty) {
      suggestion = '💡 建议处理「${uncompletedTasks.first.title}」';
    }

    return GestureDetector(
      onTap: () => showAIChatDialog(context),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              color: Color(0xFF6366F1),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                suggestion,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // 聊天按钮
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF6366F1),
                size: 14,
              ),
            ),
            const SizedBox(width: 4),
            // 关闭按钮
            GestureDetector(
              onTap: () => setState(() => _isAICardDismissed = true),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.textHintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTaskDetail(Task task) {
    final l = context.l;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getPriorityColor(task.priority)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.flag_rounded,
                                    size: 14,
                                    color: _getPriorityColor(task.priority),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getPriorityText(task.priority),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _getPriorityColor(task.priority),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getStatusColor(task.status)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _getStatusText(task.status),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusColor(task.status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (task.content != null &&
                            task.content!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            task.content!,
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondaryColor,
                              height: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        _buildDetailRow(
                          Icons.access_time_rounded,
                          l.deadline,
                          task.dueTimeDescription,
                        ),
                        if (task.createdAt != null)
                          _buildDetailRow(
                            Icons.add_circle_outline,
                            l.createTime,
                            _formatDateTime(task.createdAt!),
                          ),
                        if (task.assigneeUserId != null && task.assigneeUserId!.isNotEmpty)
                          _buildAssigneeRow(task),
                        const SizedBox(height: 24),
                        _buildStatusSelector(task),
                        const SizedBox(height: 24),
                        _buildTaskCommentsSection(task),
                        const SizedBox(height: 24),
                        _buildDistributionStatusSection(task),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _editTask(task);
                            },
                            icon: const Icon(Icons.edit_rounded),
                            label: Text(l.editTask),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showDistributeTaskDialog(task),
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('分发给团队成员'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusSelector(Task task) {
    final l = context.l;
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: AppTheme.textSecondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.changeStatus,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildStatusButton(
                    TaskStatus.pending,
                    l.statusPending,
                    Icons.schedule_rounded,
                    AppTheme.warningColor,
                    task,
                    provider,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusButton(
                    TaskStatus.inProgress,
                    l.statusInProgress,
                    Icons.play_arrow_rounded,
                    AppTheme.infoColor,
                    task,
                    provider,
                  ),
                  const SizedBox(width: 8),
                  _buildStatusButton(
                    TaskStatus.completed,
                    l.statusCompleted,
                    Icons.check_circle_rounded,
                    AppTheme.successColor,
                    task,
                    provider,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusButton(
    TaskStatus status,
    String label,
    IconData icon,
    Color color,
    Task task,
    TaskProvider provider,
  ) {
    final isSelected = task.status == status;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!isSelected) {
            _changeTaskStatus(task.id, status, provider);
            Navigator.pop(context);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? color : AppTheme.textHintColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? color : AppTheme.textHintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeTaskStatus(
      String taskId, TaskStatus newStatus, TaskProvider provider) {
    provider.updateTaskStatus(taskId, newStatus);
  }

  void _changeTaskPriority(
      String taskId, TaskPriority newPriority, TaskProvider provider) {
    final l = context.l;
    final taskIndex = provider.tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = provider.tasks[taskIndex];
    final updatedTask = task.copyWith(priority: newPriority);
    provider.updateTask(updatedTask);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.flag_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text('${l.priority}  ${_getPriorityText(newPriority)}'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: AppTheme.primaryColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _editDueTime(Task task, TaskProvider provider) {
    final l = context.l;
    DateTime selectedDate = task.dueTime ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(l.selectDeadline,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 365)),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              selectedDate = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              );
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                              '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                              builder: (context, child) {
                                return MediaQuery(
                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                );
                              },
                            );
                            if (time != null) {
                              selectedTime = time;
                              selectedDate = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                time.hour,
                                time.minute,
                              );
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: Text(
                              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            final updatedTask = task.copyWith(dueTime: null);
                            provider.updateTask(updatedTask);
                            Navigator.pop(context);
                          },
                          child: const Text('清除截止时间'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final updatedTask =
                                task.copyWith(dueTime: selectedDate);
                            provider.updateTask(updatedTask);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(l.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editReminder(Task task, TaskProvider provider) {
    final l = context.l;
    int selectedMinutes = task.reminderMinutes ?? 30;
    final options = [5, 15, 30, 60, 120, 1440]; // 分钟
    final labels = [
      '${l.reminder5Min}',
      '${l.reminder15Min}',
      '${l.reminder30Min}',
      '${l.reminder1Hour}',
      '${l.reminder2Hour}',
      '${l.reminder1Day}'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.reminder,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(options.length, (index) {
                      final isSelected = selectedMinutes == options[index];
                      return GestureDetector(
                        onTap: () {
                          selectedMinutes = options[index];
                          final updatedTask =
                              task.copyWith(reminderMinutes: selectedMinutes);
                          provider.updateTask(updatedTask);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor.withValues(alpha: 0.15)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            labels[index],
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondaryColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      final updatedTask = task.copyWith(reminderMinutes: null);
                      provider.updateTask(updatedTask);
                      Navigator.pop(context);
                    },
                    child: Text(l.off),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editRecurring(Task task, TaskProvider provider) {
    final l = context.l;
    String? selectedRule = task.recurringRule;
    final options = [null, 'daily', 'weekly', 'monthly'];
    final labels = [l.noRepeat, l.dailyRepeat, l.weeklyRepeat, l.monthlyRepeat];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.repeatCycle,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(options.length, (index) {
                      final isSelected = selectedRule == options[index];
                      return GestureDetector(
                        onTap: () {
                          selectedRule = options[index];
                          final updatedTask = task.copyWith(
                            isRecurring: options[index] != null,
                            recurringRule: options[index],
                          );
                          provider.updateTask(updatedTask);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor.withValues(alpha: 0.15)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            labels[index],
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondaryColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateTaskTags(
      String taskId, List<String> tagIds, TaskProvider provider) {
    final taskIndex = provider.tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = provider.tasks[taskIndex];
    final updatedTask = task.copyWith(tagIds: tagIds);
    provider.updateTask(updatedTask);
  }

  void _editTask(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(task: task),
      ),
    );
  }

  Widget _buildTaskCommentsSection(Task task) {
    final currentUserId = BackendApiService.instance.userId;
    return FutureBuilder<List<TaskComment>>(
      future: _commentsFutureCache.putIfAbsent(task.id, () => TaskCommentService.instance.getComments(task.id)),
      builder: (context, snapshot) {
        final allComments = snapshot.data ?? [];
        final comments = allComments.where((c) => c.authorUserId == currentUserId).toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    '任务评论',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _showAddCommentDialog(task),
                    child: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (comments.isEmpty)
                Text(
                  '暂无评论',
                  style: TextStyle(color: AppTheme.textSecondaryColor),
                )
              else
                ...comments.map(
                  (comment) => Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.content,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDateTime(comment.createdAt)} · ${comment.synced ? '已同步' : comment.syncError == null ? '待同步' : '同步失败'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: comment.syncError == null
                                ? AppTheme.textHintColor
                                : AppTheme.errorColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAddCommentDialog(Task task) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('添加评论'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '输入任务进展、说明或反馈',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty) return;
              try {
                final localComment =
                    await TaskCommentService.instance.addLocalComment(
                  taskId: task.id,
                  content: content,
                );

                // 先同步到后端，再关闭对话框
                if (BackendApiService.instance.isLoggedIn) {
                  try {
                    await BackendApiService.instance.pushTask(task);
                    await BackendApiService.instance.addComment(
                      taskId: task.id,
                      content: content,
                      clientCommentId: localComment.id,
                      operationId: localComment.operationId,
                    );
                    await TaskCommentService.instance
                        .markSynced(localComment.id);
                  } catch (syncError) {
                    await TaskCommentService.instance
                        .markSyncFailed(localComment.id, syncError);
                  }
                }

                if (!mounted) return;
                Navigator.pop(context);
                Navigator.pop(context);
                _commentsFutureCache.remove(task.id);
                _showTaskDetail(task);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('评论失败：$e')),
                );
              }
            },
            child: const Text('发布'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadTeamAndMembers() async {
    try {
      final teams = await BackendApiService.instance.getMyTeams();
      if (teams.isEmpty) return null;
      final teamId = teams.first['id'] as String;
      final members = await BackendApiService.instance.getTeamMembers(teamId);
      return {'teamId': teamId, 'members': members};
    } catch (_) {
      return null;
    }
  }

  void _showDistributeTaskDialog(Task task) {
    final remarkController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.62,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '分发给团队成员',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarkController,
                    decoration: const InputDecoration(
                      labelText: '分发备注',
                      hintText: '可选，例如处理要求或背景说明',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future: _loadTeamAndMembers(),
                      builder: (context, snapshot) {
                        if (!BackendApiService.instance.isLoggedIn) {
                          return const Center(child: Text('请先在设置页登录后台同步'));
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.data == null) {
                          return const Center(child: Text('您尚未加入任何团队，请先在后台创建或加入团队'));
                        }
                        final teamId = snapshot.data!['teamId'] as String;
                        final members = snapshot.data!['members'] as List<BackendTeamMember>;
                        if (members.isEmpty) {
                          return const Center(child: Text('暂无团队成员'));
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: members.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: member.online
                                    ? AppTheme.successColor.withValues(alpha: 0.15)
                                    : AppTheme.textHintColor.withValues(alpha: 0.15),
                                child: Icon(
                                  member.online
                                      ? Icons.person_rounded
                                      : Icons.person_off_rounded,
                                  color: member.online
                                      ? AppTheme.successColor
                                      : AppTheme.textHintColor,
                                ),
                              ),
                              title: Text(member.displayName),
                              subtitle: Text(
                                '${member.role} ${member.phoneMasked ?? ''}',
                              ),
                              trailing: const Icon(Icons.send_rounded),
                              onTap: () async {
                                try {
                                  await BackendApiService.instance
                                      .pushTask(task);
                                  await BackendApiService.instance
                                      .distributeTask(
                                    sourceTaskId: task.id,
                                    recipientUserId: member.userId,
                                    teamId: teamId,
                                    remark: remarkController.text.trim().isEmpty
                                        ? null
                                        : remarkController.text.trim(),
                                  );
                                  if (!mounted) return;
                                  _distributionsFutureCache.remove(task.id);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('已分发给 ${member.displayName}'),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('分发失败：$e')),
                                  );
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getDistributionStatusText(String status) {
    switch (status) {
      case 'generated':
      case 'sent':
        return '已发送';
      case 'received':
        return '已接收';
      case 'viewed':
        return '已查看';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }

  Color _getDistributionStatusColor(String status) {
    switch (status) {
      case 'generated':
      case 'sent':
        return AppTheme.infoColor;
      case 'received':
        return AppTheme.warningColor;
      case 'viewed':
        return AppTheme.primaryColor;
      case 'completed':
        return AppTheme.successColor;
      case 'failed':
        return AppTheme.errorColor;
      default:
        return AppTheme.textHintColor;
    }
  }

  String _getRecipientTaskStatusText(String? status) {
    switch (status) {
      case 'pending':
        return '待处理';
      case 'in_progress':
        return '进行中';
      case 'completed':
        return '已完成';
      case 'cancelled':
        return '已取消';
      default:
        return '';
    }
  }

  Widget _buildDistributionStatusSection(Task task) {
    if (!BackendApiService.instance.isLoggedIn) return const SizedBox.shrink();
    return FutureBuilder<List<BackendDistribution>>(
      future: _distributionsFutureCache.putIfAbsent(task.id, () => BackendApiService.instance.getDistributionsForTask(task.id)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final distributions = snapshot.data ?? [];
        if (distributions.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.send_rounded, size: 18, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    '分发状态',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${distributions.length}',
                      style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...distributions.map((d) => _buildDistributionItem(d)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDistributionItem(BackendDistribution d) {
    final statusColor = _getDistributionStatusColor(d.status);
    final statusText = _getDistributionStatusText(d.status);
    final recipientLabel = d.recipientName ?? '未知';
    final taskStatusText = _getRecipientTaskStatusText(d.recipientTaskStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(Icons.person_rounded, size: 16, color: statusColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recipientLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              DistributionStatusWidget(status: d.status, compact: true),
            ],
          ),
          if (taskStatusText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.assignment_rounded, size: 14, color: AppTheme.textSecondaryColor),
                const SizedBox(width: 4),
                Text(
                  '对方任务状态：$taskStatusText',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
                ),
              ],
            ),
          ],
          // Tappable comment summary → opens full comments
          if (d.commentCount > 0) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _showRecipientCommentsDialog(d),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.infoColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        d.lastCommentSummary != null
                            ? '${d.commentCount}条评论：${d.lastCommentSummary!}'
                            : '${d.commentCount}条评论',
                        style: TextStyle(fontSize: 12, color: AppTheme.infoColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (d.unreadCommentCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${d.unreadCommentCount}条新评论',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 16, color: AppTheme.textHintColor),
                  ],
                ),
              ),
            ),
          ],
          // Status change timeline
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _showStatusTimelineDialog(d),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 14, color: AppTheme.textSecondaryColor),
                  const SizedBox(width: 4),
                  Text(
                    '状态变更日志',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondaryColor),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 16, color: AppTheme.textHintColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _tryAckViewed(BackendDistribution d) {
    final userId = BackendApiService.instance.userId;
    if (userId != null && d.recipientUserId == userId && d.status == 'received') {
      context.read<TaskProvider>().ackDistributionViewed(d.id);
    }
  }

  void _showRecipientCommentsDialog(BackendDistribution d) {
    final currentUserId = BackendApiService.instance.userId;
    _tryAckViewed(d);
    BackendApiService.instance.markCommentsRead(d.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${d.recipientName ?? "对方"}的评论',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<BackendTaskComment>>(
                  future: _recipientCommentsFutureCache.putIfAbsent(d.id, () => BackendApiService.instance.getRecipientComments(d.id)),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final allComments = snapshot.data ?? [];
                    final comments = allComments.where((c) => c.authorUserId != currentUserId).toList();
                    if (comments.isEmpty) {
                      return const Center(child: Text('暂无评论'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: comments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = comments[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    c.authorName ?? '未知',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDateTime(c.serverCreatedAt),
                                    style: TextStyle(fontSize: 11, color: AppTheme.textHintColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(c.content, style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatusTimelineDialog(BackendDistribution d) {
    _tryAckViewed(d);
    final statusLabels = {
      'pending': '待处理',
      'in_progress': '进行中',
      'completed': '已完成',
      'cancelled': '已取消',
    };
    final sourceLabels = {
      'sender': '发送方',
      'recipient': '接收方',
      'admin': '管理员',
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '状态变更日志',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<StatusChangeLog>>(
                  future: BackendApiService.instance.getStatusChangeLogs(d.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final logs = snapshot.data ?? [];
                    if (logs.isEmpty) {
                      return const Center(child: Text('暂无状态变更记录'));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final sourceColor = log.source == 'recipient'
                            ? AppTheme.infoColor
                            : log.source == 'admin'
                                ? Colors.orange
                                : AppTheme.successColor;
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timeline line + dot
                              SizedBox(
                                width: 32,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: sourceColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (index < logs.length - 1)
                                      Expanded(
                                        child: Container(width: 2, color: Colors.grey.shade300),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Content
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            log.changedByName ?? '未知',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sourceColor),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: sourceColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              sourceLabels[log.source] ?? log.source,
                                              style: TextStyle(fontSize: 10, color: sourceColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${statusLabels[log.previousStatus] ?? log.previousStatus} → ${statusLabels[log.newStatus] ?? log.newStatus}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatDateTime(log.createdAt),
                                        style: TextStyle(fontSize: 11, color: AppTheme.textHintColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textHintColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _getPriorityText(TaskPriority priority) {
    final l = context.l;
    switch (priority) {
      case TaskPriority.high:
        return l.priorityHigh;
      case TaskPriority.medium:
        return l.priorityMedium;
      case TaskPriority.low:
        return l.priorityLow;
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return AppTheme.errorColor;
      case TaskPriority.medium:
        return AppTheme.warningColor;
      case TaskPriority.low:
        return AppTheme.successColor;
    }
  }

  String _getStatusText(TaskStatus status) {
    final l = context.l;
    switch (status) {
      case TaskStatus.pending:
        return l.statusPending;
      case TaskStatus.inProgress:
        return l.statusInProgress;
      case TaskStatus.completed:
        return l.statusCompleted;
      case TaskStatus.cancelled:
        return l.statusCancelled;
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return AppTheme.warningColor;
      case TaskStatus.inProgress:
        return AppTheme.infoColor;
      case TaskStatus.completed:
        return AppTheme.successColor;
      case TaskStatus.cancelled:
        return AppTheme.textHintColor;
    }
  }

  void _completeTask(String id, TaskProvider provider) {
    final l = context.l;
    final taskIndex = provider.tasks.indexWhere((t) => t.id == id);
    if (taskIndex == -1) return;
    final task = provider.tasks[taskIndex];
    provider.updateTaskStatus(id, TaskStatus.completed);

    if (task.isRecurring) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('周期任务「${task.title}」已完成，已自动创建下一期')),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text(l.taskComplete),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  void _deleteTask(String id, TaskProvider provider) {
    final l = context.l;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.confirmDelete),
        content: Text(l.confirmDeleteHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              provider.deleteTask(id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(l.taskDelete),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(l.delete),
          ),
        ],
      ),
    );
  }

  void _startTask(String id, TaskProvider provider) {
    final l = context.l;
    provider.startTask(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.play_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Text(l.taskStart),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: AppTheme.infoColor,
      ),
    );
  }

  Widget _buildCompletedSection(TaskProvider provider) {
    final l = context.l;
    // 从全部任务中获取已完成任务，确保数量与实际一致
    final completedTasks = provider.completedTasks;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 可点击的标题栏
          InkWell(
            onTap: () =>
                setState(() => _isCompletedExpanded = !_isCompletedExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.successColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.completed,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${completedTasks.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 展开/收起图标
                  AnimatedRotation(
                    turns: _isCompletedExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textHintColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的任务列表
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: completedTasks.map((task) {
                return Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: TaskCard(
                    task: task,
                    onTap: () => _showTaskDetail(task),
                    isDistributed: provider.distributedTaskIds.contains(task.id),
                    onComplete: () => _restoreTask(task.id, provider),
                    onDelete: () => _deleteTask(task.id, provider),
                    onStatusChange: (status) =>
                        _changeTaskStatus(task.id, status, provider),
                    onPriorityChange: (priority) =>
                        _changeTaskPriority(task.id, priority, provider),
                    onDueTimeTap: () => _editDueTime(task, provider),
                    onReminderTap: () => _editReminder(task, provider),
                    onRecurringTap: () => _editRecurring(task, provider),
                    availableTags: _getAllTags(provider),
                    onTagsChanged: (tagIds) =>
                        _updateTaskTags(task.id, tagIds, provider),
                  ),
                );
              }).toList(),
            ),
            crossFadeState: _isCompletedExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  void _restoreTask(String id, TaskProvider provider) {
    final l = context.l;
    provider.restoreTask(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.restore_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text(l.taskRestore),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: AppTheme.warningColor,
      ),
    );
  }

  /// 获取包含默认标签的完整标签列表
  List<Tag> _getAllTags(TaskProvider provider) {
    // 默认标签
    final defaultTags = Tag.getDefaultTags();

    // 合并默认标签和自定义标签（去重）
    final allTags = [...defaultTags];
    for (final tag in provider.tags) {
      if (!defaultTags.any((t) => t.id == tag.id)) {
        allTags.add(tag);
      }
    }

    return allTags;
  }

  List<Task> _getFilteredTaskList(TaskProvider provider) {
    var tasks = _selectedFilter == 'overdue'
        ? provider.overdueTasks
        : provider.filteredTasks;

    // 标签筛选
    if (_selectedTagId != null) {
      tasks = tasks.where((t) => t.tagIds.contains(_selectedTagId)).toList();
    }

    return tasks;
  }

  // ---- Notification & Activity helpers (B6, B7) ----

  Future<void> _loadUnreadCount() async {
    final count = await BackendApiService.instance.getUnreadNotificationCount();
    if (mounted) setState(() => _unreadNotificationCount = count);
  }

  void _showActivityFeed() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ActivityFeedDialog(),
    );
  }

  void _showNotificationCenter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text('通知中心', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await BackendApiService.instance.markAllNotificationsRead();
                        _loadUnreadCount();
                        Navigator.pop(context);
                      },
                      child: const Text('全部已读'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(builder: (context) {
                  final notifFuture = BackendApiService.instance.getNotifications();
                  return FutureBuilder<List<Map<String, dynamic>>>(
                  future: notifFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
                    }
                    final notifications = snapshot.data ?? [];
                    if (notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text('暂无通知', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (context, index) {
                        final n = notifications[index];
                        final read = n['read'] as bool? ?? false;
                        final title = n['title'] as String? ?? '';
                        final body = n['body'] as String? ?? '';
                        final createdAt = n['createdAt'] as String? ?? '';
                        final type = n['type'] as String? ?? '';
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (read ? Colors.grey : AppTheme.primaryColor).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              type == 'mention' ? Icons.alternate_email_rounded
                                  : type == 'assignment' ? Icons.person_pin_rounded
                                  : type == 'distribution' ? Icons.send_rounded
                                  : Icons.info_outline,
                              size: 18,
                              color: read ? Colors.grey : AppTheme.primaryColor,
                            ),
                          ),
                          title: Text(title, style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600, fontSize: 14)),
                          subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: read ? Colors.transparent : AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          onTap: () async {
                            if (!read) {
                              await BackendApiService.instance.markNotificationRead(n['id'] as String);
                              _loadUnreadCount();
                            }
                          },
                        );
                      },
                    );
                  },
                    );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Task Assignment (B5) ----

  Widget _buildAssigneeRow(Task task) {
    final nameFuture = _resolveUserName(task.assigneeUserId!);
    return FutureBuilder<String>(
      future: nameFuture,
      builder: (context, snapshot) {
        final name = snapshot.data ?? '加载中...';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.textSecondaryColor),
              const SizedBox(width: 8),
              Text('指派给', style: TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_rounded, size: 14, color: AppTheme.primaryColor),
                    const SizedBox(width: 4),
                    Text(name, style: TextStyle(fontSize: 13, color: AppTheme.primaryColor, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                onPressed: () => _showAssignTaskDialog(task),
                tooltip: '更改指派',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  static final Map<String, String> _userNameCache = {};

  Future<String> _resolveUserName(String userId) async {
    if (_userNameCache.containsKey(userId)) return _userNameCache[userId]!;
    try {
      final teams = await BackendApiService.instance.getMyTeams();
      if (teams.isEmpty) return userId;
      final members = await BackendApiService.instance.getTeamMembers(teams.first['id'] as String);
      for (final m in members) {
        _userNameCache[m.userId] = m.displayName;
      }
      return _userNameCache[userId] ?? userId;
    } catch (_) {
      return userId;
    }
  }

  void _showAssignTaskDialog(Task task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.person_add_rounded, color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    const Text('指派任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(height: 1),
              FutureBuilder<Map<String, dynamic>?>(
                future: _loadTeamAndMembers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('未加入团队，无法指派', style: TextStyle(color: AppTheme.textSecondaryColor)),
                    );
                  }
                  final members = data['members'] as List<BackendTeamMember>;
                  final currentUserId = BackendApiService.instance.userId;
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final m = members[index];
                      final isCurrentAssignee = task.assigneeUserId == m.userId;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrentAssignee ? AppTheme.primaryColor : Colors.grey.shade300,
                          child: Text(
                            m.displayName.isNotEmpty ? m.displayName[0] : '?',
                            style: TextStyle(color: isCurrentAssignee ? Colors.white : Colors.grey.shade700, fontSize: 14),
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: m.userId == currentUserId ? const Text('（自己）', style: TextStyle(fontSize: 11)) : null,
                        trailing: isCurrentAssignee
                            ? const Icon(Icons.check_circle, color: AppTheme.primaryColor)
                            : null,
                        onTap: () {
                          final provider = context.read<TaskProvider>();
                          provider.updateTask(task.copyWith(assigneeUserId: m.userId));
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateRangeChip(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    final hasValue = value != null;
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2027),
        );
        onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasValue ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: hasValue ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range, size: 14, color: hasValue ? AppTheme.primaryColor : Colors.grey[500]),
            const SizedBox(width: 4),
            Text(
              hasValue ? '${value.month}/${value.day}' : label,
              style: TextStyle(fontSize: 12, color: hasValue ? AppTheme.primaryColor : Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecentSearches(TaskProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('最近搜索', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
                TextButton(
                  onPressed: () {
                    provider.clearRecentSearches();
                    Navigator.pop(context);
                  },
                  child: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.recentSearches.map((s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                onPressed: () {
                  provider.setSearchQuery(s);
                  Navigator.pop(context);
                },
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchToolbar(TaskProvider provider) {
    final allTasks = _getFilteredTaskList(provider)
        .where((t) => t.parentId == null)
        .toList();
    final allSelected = allTasks.isNotEmpty && allTasks.every((t) => _selectedTaskIds.contains(t.id));
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: AppTheme.primaryColor.withValues(alpha: 0.06),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedTaskIds.addAll(allTasks.map((t) => t.id));
              } else {
                _selectedTaskIds.clear();
              }
            }),
          ),
          Text('已选 ${_selectedTaskIds.length} 项', style: const TextStyle(fontSize: 13)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 20),
            tooltip: '标记完成',
            onPressed: _selectedTaskIds.isEmpty ? null : () async {
              await provider.batchUpdateTasks(_selectedTaskIds.toList(), status: TaskStatus.completed);
              setState(() { _selectedTaskIds.clear(); });
            },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            tooltip: '开始进行',
            onPressed: _selectedTaskIds.isEmpty ? null : () async {
              await provider.batchUpdateTasks(_selectedTaskIds.toList(), status: TaskStatus.inProgress);
              setState(() { _selectedTaskIds.clear(); });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '批量删除',
            onPressed: _selectedTaskIds.isEmpty ? null : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text('确定要删除选中的 ${_selectedTaskIds.length} 个任务吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('删除')),
                  ],
                ),
              );
              if (confirm == true) {
                await provider.batchDeleteTasks(_selectedTaskIds.toList());
                setState(() { _selectedTaskIds.clear(); });
              }
            },
          ),
        ],
      ),
    );
  }
}
