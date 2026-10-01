import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/task_comment.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';
import '../widgets/quick_add_modal.dart';
import '../widgets/task_list_skeleton.dart';
import '../widgets/task_template_dialog.dart';
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
import '../widgets/error_state_widget.dart';
import '../widgets/subtask_list.dart';
import '../widgets/activity_feed_dialog.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/conflict_resolution_dialog.dart';

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
  bool _isUndoExpanded = true;
  bool _isRecycleBinExpanded = false; // 回收站栏目展开状态
  final Map<String, TaskStatus> _undoableCompletedTasks = {};
  final List<Task> _recentlyDeleted = []; // 最近删除的任务（回收站）
  int _unreadNotificationCount = 0;
  bool _isAICardDismissed = false; // AI 建议卡片是否已关闭

  // Cached futures for FutureBuilders (prevents rebuild from re-triggering)
  final Map<String, Future<List<TaskComment>>> _commentsFutureCache = {};
  VoidCallback?
      _triggerCommentsRefresh; // 详情页评论区刷新回调（由 sheet 内 StatefulBuilder 注入）
  final Map<String, Future<List<BackendDistribution>>>
      _distributionsFutureCache = {};
  final Map<String, Future<List<BackendTaskComment>>>
      _recipientCommentsFutureCache = {};
  final Map<String, bool> _commentsExpanded = {};
  Future<Map<String, dynamic>?>? _teamAndMembersFuture;

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

    // 恢复被系统设置中断前的页面（如设置页）
    _restoreNavigationState();
  }

  /// 恢复导航状态：APP从系统设置返回后若进程被杀，恢复到之前的tab
  Future<void> _restoreNavigationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restoreTab = prefs.getInt('_restore_tab_index');
      if (restoreTab != null) {
        await prefs.remove('_restore_tab_index');
        if (mounted && restoreTab >= 0 && restoreTab <= 4) {
          setState(() => _currentIndex = restoreTab);
        }
      }
    } catch (_) {}
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
                    // 顶部工具栏（同步失败时换行，同步 chip 单独第二行，避免和天气 chip 挤）
                    Builder(builder: (context) {
                      final syncFailed = provider.backendSyncError != null &&
                          provider.backendSyncError!.isNotEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    // 天气紧凑图标
                                    _buildWeatherChip(),
                                    const SizedBox(width: 8),
                                    // 云同步 chip：非失败时在第一行
                                    if (!syncFailed) ...[
                                      _buildSyncDot(provider),
                                      const SizedBox(width: 8),
                                    ],
                                    // 离线提示点
                                    StreamBuilder<List<ConnectivityResult>>(
                                      stream:
                                          Connectivity().onConnectivityChanged,
                                      initialData: const [
                                        ConnectivityResult.wifi
                                      ],
                                      builder: (context, snapshot) {
                                        final results = snapshot.data ??
                                            [ConnectivityResult.wifi];
                                        final isOffline = results
                                            .contains(ConnectivityResult.none);
                                        if (!isOffline) {
                                          return const SizedBox.shrink();
                                        }
                                        return Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
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
                          // 同步失败时，chip 单独排到第二行
                          if (syncFailed) ...[
                            const SizedBox(height: 8),
                            _buildSyncDot(provider),
                          ],
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    // 进度卡片 - 紧凑版
                    _buildProgressCard(provider),
                  ],
                ),
              ),
            ),
            // AI 建议卡片
            if (provider.todayTasks.any((t) => !t.isCompleted) &&
                !_isAICardDismissed)
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
                        style: const TextStyle(
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
            provider.todayTasks.every((t) => t.isCompleted) &&
                    provider.overdueTasks.isEmpty
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
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.6)),
                                const SizedBox(height: 12),
                                Text(
                                  l.allTasksCompleted,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l.completedTasksMsg(
                                      provider.todayTasks.length),
                                  style: const TextStyle(
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

                    // 「即将到期优先」排序：有截止时间的按 dueTime 升序在前，
                    // 无截止时间的沉到底部（保持原相对顺序，使用稳定排序）。
                    // 各组内排序后再合并：逾期区 > 今日区。
                    overdueUncompleted.sort(_compareByDueTime);
                    todayUncompleted.sort(_compareByDueTime);

                    final overdueIds =
                        overdueUncompleted.map((t) => t.id).toSet();
                    final mergedTasks = [
                      ...overdueUncompleted,
                      ...todayUncompleted
                          .where((t) => !overdueIds.contains(t.id)),
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
                                          color: AppTheme.errorColor
                                              .withValues(alpha: 0.4),
                                          width: 1.5,
                                        ),
                                      )
                                    : null,
                                child: TaskCard(
                                  task: task,
                                  onTap: () => _showTaskDetail(task),
                                  isDistributed: provider.distributedTaskIds
                                      .contains(task.id),
                                  onComplete: () =>
                                      _completeTask(task.id, provider),
                                  onDelete: () =>
                                      _deleteTask(task.id, provider),
                                  onStart: () => _startTask(task.id, provider),
                                  onStatusChange: (status) => _changeTaskStatus(
                                      task.id, status, provider),
                                  onPriorityChange: (priority) =>
                                      _changeTaskPriority(
                                          task.id, priority, provider),
                                  onDueTimeTap: () =>
                                      _editDueTime(task, provider),
                                  onReminderTap: () =>
                                      _editReminder(task, provider),
                                  onRecurringTap: () =>
                                      _editRecurring(task, provider),
                                  availableTags: _getAllTags(provider),
                                  onTagsChanged: (tagIds) => _updateTaskTags(
                                      task.id, tagIds, provider),
                                  onSaveAsTemplate: () =>
                                      _saveAsTemplate(task, provider),
                                ),
                              ),
                            );
                          },
                          childCount: mergedTasks.length,
                        ),
                      ),
                    );
                  }),
            if (_undoableCompletedTasks.isNotEmpty)
              SliverToBoxAdapter(child: _buildUndoSection(provider)),
            // 已完成任务分组（从全部任务中获取已完成任务，不受 todayTasks 过滤限制）
            if (provider.completedTasks
                .any((task) => !_undoableCompletedTasks.containsKey(task.id)))
              SliverToBoxAdapter(
                child: _buildCompletedSection(provider),
              ),
            // 回收站（最近删除的任务，可恢复）
            if (_recentlyDeleted.isNotEmpty)
              SliverToBoxAdapter(child: _buildRecycleBinSection(provider)),
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
                      Row(
                        children: [
                          Text(
                            l.navAll,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          _buildStatsEntryButton(),
                        ],
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
                                onSubmitted: (_) => provider.commitSearch(),
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
                                _buildTagFilterChip(null, l.allTags, null),
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
                          _buildDateRangeChip(
                              l.dateFrom, provider.filterDateFrom, (dt) {
                            provider.setFilterDateRange(
                                dt, provider.filterDateTo);
                          }),
                          const SizedBox(width: 8),
                          _buildDateRangeChip(l.dateTo, provider.filterDateTo,
                              (dt) {
                            provider.setFilterDateRange(
                                provider.filterDateFrom, dt);
                          }),
                          if (provider.filterDateFrom != null ||
                              provider.filterDateTo != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: GestureDetector(
                                onTap: () =>
                                    provider.setFilterDateRange(null, null),
                                child: Icon(Icons.clear,
                                    size: 16, color: Colors.grey[400]),
                              ),
                            ),
                          const Spacer(),
                          // Recent searches
                          if (provider.recentSearches.isNotEmpty &&
                              provider.searchQuery.isEmpty)
                            GestureDetector(
                              onTap: () => _showRecentSearches(provider),
                              child: Icon(Icons.history,
                                  size: 20, color: Colors.grey[400]),
                            ),
                          const SizedBox(width: 8),
                          // Batch mode toggle
                          GestureDetector(
                            onTap: () => setState(() {
                              _isBatchMode = !_isBatchMode;
                              if (!_isBatchMode) _selectedTaskIds.clear();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isBatchMode
                                    ? AppTheme.primaryColor
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.checklist,
                                      size: 16,
                                      color: _isBatchMode
                                          ? Colors.white
                                          : Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(l.batchMode,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _isBatchMode
                                              ? Colors.white
                                              : Colors.grey[600])),
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
              // 加载中：显示骨架屏，避免空数据时误显示"无任务"
              if (provider.isLoading && provider.tasks.isEmpty)
                const SliverToBoxAdapter(child: TaskListSkeleton(itemCount: 4))
              else if (_getFilteredTaskList(provider).isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyState(isWhite: true),
                )
              else
                Builder(builder: (context) {
                  // toList() 复制一份，避免就地排序污染 provider 内部的 _tasks
                  final filteredTasks = _getFilteredTaskList(provider).toList();
                  // 「即将到期优先」：在当前筛选结果内按 dueTime 升序，
                  // 无截止时间的任务沉底（与今日页排序规则一致）。
                  filteredTasks.sort(_compareByDueTime);
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final task = filteredTasks[index];
                          if (task.parentId != null) {
                            return const SizedBox.shrink();
                          }
                          final subtasks =
                              provider.subtasksByParentId[task.id] ?? [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TaskCard(
                                  task: task,
                                  onTap: _isBatchMode
                                      ? () => setState(() {
                                            if (_selectedTaskIds
                                                .contains(task.id)) {
                                              _selectedTaskIds.remove(task.id);
                                            } else {
                                              _selectedTaskIds.add(task.id);
                                            }
                                          })
                                      : () => _showTaskDetail(task),
                                  isDistributed: provider.distributedTaskIds
                                      .contains(task.id),
                                  isPinned: provider.isPinned(task.id),
                                  onPinToggle: () => provider.isPinned(task.id)
                                      ? provider.unpinTask(task.id)
                                      : provider.pinTask(task.id),
                                  selectable: _isBatchMode,
                                  isSelected:
                                      _selectedTaskIds.contains(task.id),
                                  onSelectionChanged: (v) => setState(() {
                                    if (v) {
                                      _selectedTaskIds.add(task.id);
                                    } else {
                                      _selectedTaskIds.remove(task.id);
                                    }
                                  }),
                                  onComplete: () =>
                                      _completeTask(task.id, provider),
                                  onDelete: () =>
                                      _deleteTask(task.id, provider),
                                  onStart: () => _startTask(task.id, provider),
                                  onStatusChange: (status) => _changeTaskStatus(
                                      task.id, status, provider),
                                  onPriorityChange: (priority) =>
                                      _changeTaskPriority(
                                          task.id, priority, provider),
                                  onDueTimeTap: () =>
                                      _editDueTime(task, provider),
                                  onReminderTap: () =>
                                      _editReminder(task, provider),
                                  onRecurringTap: () =>
                                      _editRecurring(task, provider),
                                  availableTags: _getAllTags(provider),
                                  onTagsChanged: (tagIds) => _updateTaskTags(
                                      task.id, tagIds, provider),
                                  onSaveAsTemplate: () =>
                                      _saveAsTemplate(task, provider),
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
                                      Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AddTaskScreen(
                                                parentId: task.id),
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
                      fontSize: 12,
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
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
            if (_weatherInfo?.cityName != null) ...[
              const SizedBox(width: 3),
              Text(
                _weatherInfo!.cityName,
                style: const TextStyle(
                  fontSize: 12,
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

  /// 云同步状态（顶栏用，带图标与文字，替代原先难以发现的色点）
  Widget _buildSyncDot(TaskProvider provider) {
    final l = context.l;
    final loggedIn = provider.isBackendLoggedIn;
    final isSyncing = provider.isBackendSyncing;
    final hasError = provider.backendSyncError != null &&
        provider.backendSyncError!.isNotEmpty;

    Color color;
    String label;
    String tooltip;
    IconData icon;
    VoidCallback onTap;

    if (!loggedIn) {
      color = AppTheme.textHintColor;
      label = l.syncLabelOff;
      tooltip = l.syncNotLoggedIn;
      icon = Icons.cloud_off_rounded;
      onTap = () => setState(() => _currentIndex = 4);
    } else if (isSyncing) {
      color = AppTheme.infoColor;
      label = l.syncLabelSyncing;
      tooltip = l.syncing;
      icon = Icons.sync_rounded;
      onTap = () {};
    } else if (hasError) {
      color = AppTheme.errorColor;
      label = l.syncFailedShort;
      tooltip = l.syncFailedRetry;
      icon = Icons.error_outline_rounded;
      onTap = () async {
        try {
          final count = await provider.syncAllWithBackend();
          if (!mounted) return;
          if (provider.hasConflicts) {
            await showConflictDialogIfNeeded(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.syncCompletedCount(count))),
            );
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.syncFailedError(e))),
          );
        }
      };
    } else {
      color = AppTheme.successColor;
      label = l.synced;
      tooltip = provider.lastBackendSyncAt == null
          ? l.syncEnabled
          : l.lastSyncAt(_formatDateTime(provider.lastBackendSyncAt!));
      icon = Icons.cloud_done_rounded;
      onTap = () async {
        try {
          final count = await provider.syncAllWithBackend();
          if (!mounted) return;
          if (provider.hasConflicts) {
            await showConflictDialogIfNeeded(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.syncCompletedCount(count))),
            );
          }
        } catch (_) {}
      };
    }

    final iconChild = isSyncing
        ? SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          )
        : Icon(icon, size: 14, color: color);

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: hasError
                ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconChild,
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
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

  /// 打开统计页面（从「全部任务」页进入）
  void _openStats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatsScreen(
          onNavigateToAllTasks: () => Navigator.pop(context),
          onNavigateToFiltered: (filter) {
            Navigator.pop(context);
            setState(() {
              _currentIndex = 1;
              if (filter == 'overdue') {
                _selectedFilter = 'overdue';
                context.read<TaskProvider>().setFilterStatus(null);
              }
            });
          },
        ),
      ),
    );
  }

  /// 「全部任务」页顶部的「统计」入口按钮
  Widget _buildStatsEntryButton() {
    final l = context.l;
    return GestureDetector(
      onTap: _openStats,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded,
                size: 16, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(
              l.navStats,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
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
              _buildNavItem(2, Icons.event_repeat_rounded, l.navHabit),
              _buildNavItem(3, Icons.calendar_month_rounded, l.navCalendar),
              _buildNavItem(4, Icons.settings_rounded, l.navSettings),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 模板快捷入口（小按钮，点击从模板创建任务）
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            tooltip: context.l.templates,
            icon: const Icon(Icons.bookmark_rounded, size: 22),
            color: AppTheme.primaryColor,
            onPressed: _createFromTemplate,
          ),
        ),
        _buildMainFAB(),
      ],
    );
  }

  Widget _buildMainFAB() {
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
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.1),
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
                      style: const TextStyle(
                        fontSize: 12,
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
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  /// 构建AI建议卡片 - 紧凑单行横幅
  Widget _buildAISuggestionCard(TaskProvider provider) {
    final l = context.l;
    final uncompletedTasks =
        provider.todayTasks.where((t) => !t.isCompleted).toList();
    final highPriorityTasks =
        uncompletedTasks.where((t) => t.priority == TaskPriority.high).toList();
    final highPriorityTask =
        highPriorityTasks.isNotEmpty ? highPriorityTasks.first : null;

    String suggestion = l.aiNoPendingTasks;
    if (highPriorityTask != null) {
      suggestion = l.aiSuggestionPriority(highPriorityTask.title);
      if (highPriorityTask.dueTime != null) {
        suggestion += ' · ${highPriorityTask.dueTimeDescription}';
      }
    } else if (uncompletedTasks.isNotEmpty) {
      suggestion = l.aiSuggestionNext(uncompletedTasks.first.title);
    }

    return GestureDetector(
      onTap: () => showAIChatDialog(context),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
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
              child: const Icon(
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
    // 打开详情页时后台拉一次最新评论（含被指派/被分发任务），避免看不到新评论（App 无实时推送）
    _refreshCommentsFromBackend(task);
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
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
                            style: const TextStyle(
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
                        _buildDetailRow(
                          Icons.add_circle_outline,
                          l.createTime,
                          _formatDateTime(task.createdAt),
                        ),
                        Consumer<TaskProvider>(
                          builder: (_, provider, __) {
                            final t = provider.tasks.firstWhere(
                              (x) => x.id == task.id,
                              orElse: () => task,
                            );
                            if (t.assigneeUserId == null ||
                                t.assigneeUserId!.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _buildAssigneeRow(t);
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildStatusSelector(task),
                        const SizedBox(height: 24),
                        _buildTaskCommentsSection(task),
                        const SizedBox(height: 24),
                        Consumer<TaskProvider>(
                          builder: (_, provider, __) {
                            final current = provider.tasks.firstWhere(
                              (item) => item.id == task.id,
                              orElse: () => task,
                            );
                            final subtasks = provider.tasks
                                .where((item) => item.parentId == current.id)
                                .toList();
                            return _buildUnifiedTaskResources(
                              context,
                              current,
                              subtasks,
                              provider,
                            );
                          },
                        ),
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
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _duplicateTask(task),
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('复制任务'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final provider = context.read<TaskProvider>();
                                  final hasChildren = provider.tasks
                                      .any((item) => item.parentId == task.id);
                                  var includeChildren = false;
                                  if (hasChildren) {
                                    final choice = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('归档子任务'),
                                        content: const Text('是否同时归档该任务的全部子任务？'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialogContext),
                                              child: const Text('取消')),
                                          TextButton(
                                              onPressed: () => Navigator.pop(
                                                  dialogContext, false),
                                              child: const Text('仅归档父任务')),
                                          FilledButton(
                                              onPressed: () => Navigator.pop(
                                                  dialogContext, true),
                                              child: const Text('同时归档')),
                                        ],
                                      ),
                                    );
                                    if (choice == null) return;
                                    includeChildren = choice;
                                  }
                                  await provider.archiveTaskWithSubtasks(
                                    task.id,
                                    includeSubtasks: includeChildren,
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                },
                                icon: const Icon(Icons.archive_outlined,
                                    size: 18),
                                label: const Text('归档'),
                              ),
                            ),
                          ],
                        ),
                        if (BackendApiService.instance.isLoggedIn)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _teamAndMembersFuture ??=
                                _loadTeamAndMembers(),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                // 加载团队失败时等同于无团队，隐藏分发按钮即可
                                return const SizedBox.shrink();
                              }
                              final members =
                                  (snap.data?['members'] as List?) ?? const [];
                              if (members.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _showDistributeTaskDialog(task),
                                      icon: const Icon(Icons.send_rounded),
                                      label: Text(l.distributeToTeam),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primaryColor,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
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

  Widget _buildUnifiedTaskResources(
    BuildContext sheetContext,
    Task task,
    List<Task> subtasks,
    TaskProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('子任务与附件',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              tooltip: '操作历史',
              onPressed: () => showModalBottomSheet(
                context: sheetContext,
                isScrollControlled: true,
                builder: (_) => ActivityFeedDialog(
                  taskId: task.id,
                  taskTitle: task.title,
                  taskCreatedAt: task.createdAt,
                ),
              ),
              icon: const Icon(Icons.history_rounded, size: 20),
            ),
          ],
        ),
        SubtaskList(
          parentTask: task,
          subtasks: subtasks,
          onAddSubtask: () async {
            await Navigator.push(
              sheetContext,
              MaterialPageRoute(
                  builder: (_) => AddTaskScreen(parentId: task.id)),
            );
            if (mounted) setState(() {});
          },
          onSubtaskTap: (subtask) => _showTaskDetail(subtask),
        ),
        const SizedBox(height: 8),
        AttachmentPicker(
          attachmentPaths: task.attachmentPaths,
          onChanged: (paths) async {
            final removed =
                task.attachmentPaths.where((p) => !paths.contains(p));
            await provider.updateTask(task.copyWith(attachmentPaths: paths));
            await provider.cleanupUnreferencedAttachments(removed);
          },
        ),
        const SizedBox(height: 8),
        _buildDetailRow(
          Icons.update_rounded,
          '最后修改',
          _formatDateTime(task.updatedAt),
        ),
        if (task.ownerUserId != null && task.ownerUserId!.isNotEmpty)
          _buildDetailRow(
            Icons.person_outline_rounded,
            '最后修改人',
            BackendApiService.instance.userId == task.ownerUserId
                ? '我'
                : (task.assignee ?? task.ownerUserId!),
          ),
      ],
    );
  }

  Future<void> _duplicateTask(Task task) async {
    final copy = task.copyWith(
      id: const Uuid().v4(),
      title: '${task.title}（副本）',
      status: TaskStatus.pending,
      completedAt: null,
      reminderDismissed: false,
      parentId: null,
      createdAt: DateTime.now(),
    );
    await context.read<TaskProvider>().addTask(copy);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('任务副本已创建')),
      );
    }
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
                  const Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: AppTheme.textSecondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.changeStatus,
                    style: const TextStyle(
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
                  fontSize: 12,
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
              child: Column(
                children: [
                  Text(l.selectDeadline,
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                                  data: MediaQuery.of(context)
                                      .copyWith(alwaysUse24HourFormat: true),
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
                          child: Text(l.clearDeadline),
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
      (l.reminder5Min),
      (l.reminder15Min),
      (l.reminder30Min),
      (l.reminder1Hour),
      (l.reminder2Hour),
      (l.reminder1Day)
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.reminder,
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    final options = [null, 'daily', 'weekly', 'monthly', 'yearly'];
    final labels = [
      l.noRepeat,
      l.dailyRepeat,
      l.weeklyRepeat,
      l.monthlyRepeat,
      l.yearlyRepeat
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.repeatCycle,
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  /// 打开任务详情时后台拉一次最新评论（含被指派任务、分发副本），完成后触发评论区重建
  Future<void> _refreshCommentsFromBackend(Task task) async {
    if (!BackendApiService.instance.isLoggedIn) return;
    try {
      // 拉所有可见评论（含被指派任务 assignee 的评论）
      final comments = await BackendApiService.instance.pullComments();
      if (comments.isNotEmpty) {
        await TaskCommentService.instance.saveRemoteComments(comments);
      }
      // 分发评论（副本会话）
      final dists =
          await BackendApiService.instance.getDistributionsForTask(task.id);
      for (final d in dists) {
        try {
          final rc =
              await BackendApiService.instance.getRecipientComments(d.id);
          if (rc.isNotEmpty) {
            await TaskCommentService.instance.saveRemoteComments(rc);
          }
        } catch (_) {}
      }
      if (!mounted) return;
      _triggerCommentsRefresh?.call();
    } catch (_) {}
  }

  Widget _buildTaskCommentsSection(Task task) {
    final l = context.l;
    final currentUserId = BackendApiService.instance.userId;
    return StatefulBuilder(
      builder: (context, setOuter) {
        // 注入刷新回调：后台拉到新评论后清缓存并重建本 StatefulBuilder
        _triggerCommentsRefresh = () {
          _commentsFutureCache.remove(task.id);
          setOuter(() {});
        };
        return FutureBuilder<List<TaskComment>>(
          future: _commentsFutureCache.putIfAbsent(
              task.id, () => TaskCommentService.instance.getComments(task.id)),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorStateWidget(
                compact: true,
                onRetry: () {
                  _commentsFutureCache.remove(task.id);
                  setOuter(() {});
                },
              );
            }
            final allComments = snapshot.data ?? [];
            allComments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            final comments = allComments;
            final hasComments = comments.isNotEmpty;

            return StatefulBuilder(
              builder: (context, setInner) {
                final isExpanded = _commentsExpanded[task.id] ?? false;
                // 无评论时直接展开（显示空态 + 添加入口）；有评论时按折叠状态（默认折叠）
                final showContent = hasComments ? isExpanded : true;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: hasComments
                            ? () => setInner(
                                () => _commentsExpanded[task.id] = !isExpanded)
                            : () => _showAddCommentDialog(
                                task, () => setOuter(() {})),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 18, color: AppTheme.primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                l.taskComments,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimaryColor,
                                ),
                              ),
                              if (hasComments) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${comments.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (hasComments)
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 22,
                                      color: AppTheme.textHintColor),
                                )
                              else
                                const Icon(Icons.add,
                                    size: 20, color: AppTheme.primaryColor),
                            ],
                          ),
                        ),
                      ),
                      if (showContent) ...[
                        const SizedBox(height: 8),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(minHeight: 2),
                          )
                        else if (comments.isEmpty)
                          Row(
                            children: [
                              Text(
                                l.noComments,
                                style: const TextStyle(
                                    color: AppTheme.textSecondaryColor),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => _showAddCommentDialog(
                                    task, () => setOuter(() {})),
                                child: Text(l.add),
                              ),
                            ],
                          )
                        else ...[
                          ...comments.map(
                            (comment) => Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    comment.authorUserId == currentUserId
                                        ? l.me
                                        : (comment.authorName ?? l.unknown),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          comment.authorUserId == currentUserId
                                              ? AppTheme.primaryColor
                                              : AppTheme.textSecondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    comment.content,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatDateTime(comment.createdAt)} · ${comment.synced ? l.synced : comment.syncError == null ? l.pendingSync : l.syncFailedShort}',
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _showAddCommentDialog(
                                  task, () => setOuter(() {})),
                              child: Text(l.addComment),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAddCommentDialog(Task task, VoidCallback? onAdded) {
    final l = context.l;
    final controller = TextEditingController();
    String? targetTaskId; // null=全部(原任务广播)，否则=某接收方副本 taskId(定向)
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l.addComment),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 发送方有分发时，可选目标：全部(广播)或某个接收方(定向)
              FutureBuilder<List<BackendDistribution>>(
                future: _distributionsFutureCache.putIfAbsent(
                    task.id,
                    () => BackendApiService.instance
                        .getDistributionsForTask(task.id)),
                builder: (context, snap) {
                  final senderDists = (snap.data ?? [])
                      .where((d) =>
                          d.sourceTaskId == task.id &&
                          d.recipientTaskId != null)
                      .toList();
                  if (senderDists.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String?>(
                      initialValue: targetTaskId,
                      decoration: const InputDecoration(
                          labelText: '发送给', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('全部接收方')),
                        ...senderDists.map((d) => DropdownMenuItem<String?>(
                              value: d.recipientTaskId,
                              child: Text(d.recipientName ?? '接收方'),
                            )),
                      ],
                      onChanged: (v) => setDialog(() => targetTaskId = v),
                    ),
                  );
                },
              ),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l.commentHint,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.alternate_email_rounded),
                    tooltip: '@提及成员',
                    onPressed: () => _showMentionPicker(controller),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () async {
                final content = controller.text.trim();
                if (content.isEmpty) return;
                Navigator.pop(dialogContext); // 立即关闭对话框（乐观更新）
                try {
                  final localComment =
                      await TaskCommentService.instance.addLocalComment(
                    taskId: targetTaskId ?? task.id,
                    content: content,
                  );

                  // 本地已写入，立即就地刷新评论区（不等网络同步，避免等待数秒才显示）
                  if (!mounted) return;
                  _commentsFutureCache.remove(task.id);
                  _commentsExpanded[task.id] = true;
                  // 评论区可能已被用户关闭（sheet dispose），try-catch 防 setState-after-dispose 异常传播导致白屏
                  try {
                    onAdded?.call();
                  } catch (_) {}

                  // 后台同步到后端（fire-and-forget，不阻塞 UI 刷新）
                  if (BackendApiService.instance.isLoggedIn) {
                    _syncCommentToBackend(task, localComment, onAdded);
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.commentFailed(e))),
                  );
                }
              },
              child: Text(l.publish),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMentionPicker(TextEditingController controller) async {
    try {
      final data = await _loadTeamAndMembers();
      if (data == null) return;
      final members = data['members'] as List<BackendTeamMember>;
      if (members.isEmpty) return;
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => ListView(
          children: members
              .map((m) => ListTile(
                    leading: CircleAvatar(
                        child: Text(
                            m.displayName.isNotEmpty ? m.displayName[0] : '?')),
                    title: Text(m.displayName),
                    subtitle: Text('${m.role} ${m.phoneMasked ?? ''}'),
                    onTap: () => Navigator.pop(ctx, m.displayName),
                  ))
              .toList(),
        ),
      );
      if (selected == null) return;
      final text = controller.text;
      final sel = controller.selection;
      final start = sel.start >= 0 ? sel.start : text.length;
      final end = sel.end >= 0 ? sel.end : text.length;
      final insert = '@$selected ';
      controller.text = text.replaceRange(start, end, insert);
      controller.selection =
          TextSelection.collapsed(offset: start + insert.length);
    } catch (_) {}
  }

  /// 后台把评论推送到后端并更新同步状态（fire-and-forget，不阻塞 UI 刷新）
  Future<void> _syncCommentToBackend(
      Task task, TaskComment localComment, VoidCallback? onSynced) async {
    try {
      await BackendApiService.instance.pushTask(task);
      await BackendApiService.instance.addComment(
        taskId: localComment.taskId, // 定向评论用评论的目标 taskId（可能是副本），而非原任务
        content: localComment.content,
        clientCommentId: localComment.id,
        operationId: localComment.operationId,
      );
      await TaskCommentService.instance.markSynced(localComment.id);
    } catch (syncError) {
      await TaskCommentService.instance
          .markSyncFailed(localComment.id, syncError);
    }
    // 同步态变更后刷新评论区，使“待同步”及时更新为“已同步/同步失败”
    if (!mounted) return;
    _commentsFutureCache.remove(task.id);
    try {
      onSynced?.call();
    } catch (_) {}
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
    final l = context.l;
    final remarkController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final selectedUserIds = <String>{};
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
                  Text(
                    l.distributeToTeam,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarkController,
                    decoration: InputDecoration(
                      labelText: l.distributeRemark,
                      hintText: l.distributeRemarkHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setInner) {
                        return FutureBuilder<Map<String, dynamic>?>(
                          future: _loadTeamAndMembers(),
                          builder: (context, snapshot) {
                            if (!BackendApiService.instance.isLoggedIn) {
                              return Center(child: Text(l.pleaseLoginBackend));
                            }
                            if (snapshot.hasError) {
                              return ErrorStateWidget(
                                onRetry: () => setInner(() {}),
                              );
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.data == null) {
                              return Center(child: Text(l.notInAnyTeam));
                            }
                            final teamId = snapshot.data!['teamId'] as String;
                            final members = snapshot.data!['members']
                                as List<BackendTeamMember>;
                            if (members.isEmpty) {
                              return Center(child: Text(l.noTeamMembers));
                            }
                            return Column(
                              children: [
                                Expanded(
                                  child: ListView.separated(
                                    controller: scrollController,
                                    itemCount: members.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final member = members[index];
                                      final selected = selectedUserIds
                                          .contains(member.userId);
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: member.online
                                              ? AppTheme.successColor
                                                  .withValues(alpha: 0.15)
                                              : AppTheme.textHintColor
                                                  .withValues(alpha: 0.15),
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
                                        trailing: Checkbox(
                                          value: selected,
                                          onChanged: (v) => setInner(() {
                                            if (v == true) {
                                              selectedUserIds
                                                  .add(member.userId);
                                            } else {
                                              selectedUserIds
                                                  .remove(member.userId);
                                            }
                                          }),
                                        ),
                                        onTap: () => setInner(() {
                                          if (selected) {
                                            selectedUserIds
                                                .remove(member.userId);
                                          } else {
                                            selectedUserIds.add(member.userId);
                                          }
                                        }),
                                      );
                                    },
                                  ),
                                ),
                                if (selectedUserIds.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _distributeBatch(
                                          task,
                                          selectedUserIds.toList(),
                                          teamId,
                                          remarkController.text.trim(),
                                        ),
                                        icon: const Icon(Icons.send_rounded),
                                        label: Text(
                                            '分发给 ${selectedUserIds.length} 人'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppTheme.primaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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

  Future<void> _distributeBatch(
      Task task, List<String> userIds, String teamId, String remark) async {
    final l = context.l;
    final navigator = Navigator.of(context);
    try {
      await BackendApiService.instance.pushTask(task);
      int success = 0;
      for (final userId in userIds) {
        try {
          await BackendApiService.instance.distributeTask(
            sourceTaskId: task.id,
            recipientUserId: userId,
            teamId: teamId,
            remark: remark.isEmpty ? null : remark,
          );
          success++;
        } catch (_) {}
      }
      _distributionsFutureCache.remove(task.id);
      if (!mounted) return;
      navigator.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已分发给 $success/${userIds.length} 人')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.distributeFailed(e))),
      );
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

  String _getRecipientTaskStatusText(String? status, AppLocalizations l) {
    switch (status) {
      case 'pending':
        return l.statusPending;
      case 'in_progress':
        return l.statusInProgress;
      case 'completed':
        return l.statusCompleted;
      case 'cancelled':
        return l.statusCancelled;
      default:
        return '';
    }
  }

  Widget _buildDistributionStatusSection(Task task) {
    final l = context.l;
    if (!BackendApiService.instance.isLoggedIn) return const SizedBox.shrink();
    return StatefulBuilder(
      builder: (context, setInner) {
        return FutureBuilder<List<BackendDistribution>>(
          future: _distributionsFutureCache.putIfAbsent(
              task.id,
              () =>
                  BackendApiService.instance.getDistributionsForTask(task.id)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 40,
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (snapshot.hasError) {
              return ErrorStateWidget(
                compact: true,
                onRetry: () {
                  _distributionsFutureCache.remove(task.id);
                  setInner(() {});
                },
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
                      const Icon(Icons.send_rounded,
                          size: 18, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        l.distributionStatus,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${distributions.length}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600),
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
      },
    );
  }

  Widget _buildDistributionItem(BackendDistribution d) {
    final l = context.l;
    final statusColor = _getDistributionStatusColor(d.status);
    final recipientLabel = d.recipientName ?? l.unknown;
    final taskStatusText =
        _getRecipientTaskStatusText(d.recipientTaskStatus, l);

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
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              DistributionStatusWidget(status: d.status, compact: true),
            ],
          ),
          if (taskStatusText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.assignment_rounded,
                    size: 14, color: AppTheme.textSecondaryColor),
                const SizedBox(width: 4),
                Text(
                  l.counterpartTaskStatus(taskStatusText),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondaryColor),
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
                    const Icon(Icons.chat_bubble_outline_rounded,
                        size: 14, color: AppTheme.infoColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        d.lastCommentSummary != null
                            ? l.commentsCountWithSummary(
                                d.commentCount, d.lastCommentSummary!)
                            : l.commentsCount(d.commentCount),
                        style:
                            const TextStyle(fontSize: 12, color: AppTheme.infoColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (d.unreadCommentCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l.newCommentsCount(d.unreadCommentCount),
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppTheme.textHintColor),
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
                  const Icon(Icons.history_rounded,
                      size: 14, color: AppTheme.textSecondaryColor),
                  const SizedBox(width: 4),
                  Text(
                    l.statusChangeLog,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondaryColor),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.textHintColor),
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
    if (userId != null &&
        d.recipientUserId == userId &&
        d.status == 'received') {
      context.read<TaskProvider>().ackDistributionViewed(d.id);
    }
  }

  void _showRecipientCommentsDialog(BackendDistribution d) {
    final l = context.l;
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
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l.counterpartComments(d.recipientName ?? l.counterpart),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setInner) {
                    return FutureBuilder<List<BackendTaskComment>>(
                      future: _recipientCommentsFutureCache.putIfAbsent(
                          d.id,
                          () => BackendApiService.instance
                              .getRecipientComments(d.id)),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return ErrorStateWidget(
                            onRetry: () {
                              _recipientCommentsFutureCache.remove(d.id);
                              setInner(() {});
                            },
                          );
                        }
                        final allComments = snapshot.data ?? [];
                        final comments = allComments
                            .where((c) => c.authorUserId != currentUserId)
                            .toList();
                        if (comments.isEmpty) {
                          return Center(child: Text(l.noComments));
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
                                        c.authorName ?? l.unknown,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatDateTime(c.serverCreatedAt),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textHintColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(c.content,
                                      style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            );
                          },
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
    final l = context.l;
    _tryAckViewed(d);
    final statusLabels = {
      'pending': l.statusPending,
      'in_progress': l.statusInProgress,
      'completed': l.statusCompleted,
      'cancelled': l.statusCancelled,
    };
    final sourceLabels = {
      'sender': l.roleSender,
      'recipient': l.roleRecipient,
      'admin': l.roleAdmin,
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
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l.statusChangeLog,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setInner) {
                    return FutureBuilder<List<StatusChangeLog>>(
                      future:
                          BackendApiService.instance.getStatusChangeLogs(d.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return ErrorStateWidget(
                            onRetry: () => setInner(() {}),
                          );
                        }
                        final logs = snapshot.data ?? [];
                        if (logs.isEmpty) {
                          return Center(child: Text(l.noStatusChangeLogs));
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
                                            child: Container(
                                                width: 2,
                                                color: Colors.grey.shade300),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Content
                                  Expanded(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                log.changedByName ?? l.unknown,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: sourceColor),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: sourceColor.withValues(
                                                      alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  sourceLabels[log.source] ??
                                                      log.source,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: sourceColor),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${statusLabels[log.previousStatus] ?? log.previousStatus} → ${statusLabels[log.newStatus] ?? log.newStatus}',
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatDateTime(log.createdAt),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textHintColor),
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
                style: const TextStyle(
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

  /// 将任务保存为模板
  Future<void> _saveAsTemplate(Task task, TaskProvider provider) async {
    final l = context.l;
    try {
      await provider.saveTaskAsTemplate(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.savedAsTemplate),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  /// 从模板创建任务
  Future<void> _createFromTemplate() async {
    await TaskTemplateDialog.show(context);
  }

  /// 任务按截止时间升序排序的比较函数（用于「即将到期优先」）。
  ///
  /// 规则：
  /// - 都有 dueTime：按时间升序（越早越靠前）
  /// - 一方无 dueTime：无截止时间的沉到底部
  /// - 都无 dueTime：保持相等（稳定排序会保留原相对顺序）
  int _compareByDueTime(Task a, Task b) {
    final aNull = a.dueTime == null;
    final bNull = b.dueTime == null;
    if (aNull && bNull) return 0;
    if (aNull) return 1; // a 无截止时间 → 排后面
    if (bNull) return -1; // b 无截止时间 → a 排前面
    return a.dueTime!.compareTo(b.dueTime!);
  }

  Future<void> _completeTask(String id, TaskProvider provider) async {
    final l = context.l;
    final taskIndex = provider.tasks.indexWhere((t) => t.id == id);
    if (taskIndex == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务状态已变化，请刷新后重试')),
        );
      }
      return;
    }
    final task = provider.tasks[taskIndex];
    // 保存原状态，供"撤销"恢复
    final previousStatus = task.status;
    final incompleteChildren = provider.tasks
        .where((item) => item.parentId == id && !item.isCompleted)
        .toList();
    var includeChildren = false;
    if (incompleteChildren.isNotEmpty) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('完成父任务'),
          content: Text('还有 ${incompleteChildren.length} 个子任务未完成，是否一起完成？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('仅完成父任务')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('同时完成子任务')),
          ],
        ),
      );
      if (choice == null) return;
      includeChildren = choice;
    }
    try {
      await provider.completeTaskWithSubtasks(
        id,
        includeSubtasks: includeChildren,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('完成任务失败：$e')),
        );
      }
      return;
    }
    if (!mounted) return;

    if (!task.isRecurring) {
      setState(() => _undoableCompletedTasks[id] = previousStatus);
    }

    if (task.isRecurring) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l.recurringTaskCompleted(task.title))),
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
              Expanded(child: Text('${task.title} 已移至“可撤销”栏目')),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildUndoSection(TaskProvider provider) {
    final tasks = provider.completedTasks
        .where((task) => _undoableCompletedTasks.containsKey(task.id))
        .toList();
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
          InkWell(
            onTap: () => setState(() => _isUndoExpanded = !_isUndoExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.undo_rounded,
                        color: AppTheme.warningColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('可撤销',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${tasks.length}',
                      style: const TextStyle(
                          color: AppTheme.warningColor,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isUndoExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_isUndoExpanded)
            ...tasks.map((task) => ListTile(
                  leading: const Icon(Icons.check_circle,
                      color: AppTheme.successColor),
                  title: Text(task.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('任务已完成'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final previous = _undoableCompletedTasks[task.id] ??
                              TaskStatus.pending;
                          await provider.updateTaskStatus(task.id, previous);
                          if (mounted) {
                            setState(
                                () => _undoableCompletedTasks.remove(task.id));
                          }
                        },
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('撤销'),
                      ),
                      IconButton(
                        tooltip: '保留为已完成',
                        onPressed: () => setState(
                            () => _undoableCompletedTasks.remove(task.id)),
                        icon: const Icon(Icons.done_all_rounded),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
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
              // 先缓存任务到回收站，再删除
              final task = provider.tasks.where((t) => t.id == id).firstOrNull;
              if (task != null) {
                setState(() {
                  _recentlyDeleted.insert(0, task);
                  // 限制回收站最多 20 条，防止内存泄漏
                  if (_recentlyDeleted.length > 20) {
                    _recentlyDeleted.removeRange(20, _recentlyDeleted.length);
                  }
                  _isRecycleBinExpanded = true;
                });
              }
              provider.deleteTask(id).catchError((e) {
                debugPrint('删除任务失败: $e');
                // 删除失败时从回收站回滚（避免任务双份）
                if (mounted) {
                  setState(() => _recentlyDeleted.removeWhere((t) => t.id == id));
                }
              });
              // 不再用 SnackBar 提示——回收站折叠区已提供恢复入口，避免 SnackBar 不消失的问题
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

  /// 从回收站恢复任务
  Future<void> _restoreFromRecycleBin(String id, TaskProvider provider) async {
    final ok = await provider.undoDeleteTask(id);
    if (ok) {
      setState(() => _recentlyDeleted.removeWhere((t) => t.id == id));
    }
  }

  /// 回收站折叠区（类似已完成任务栏目）
  Widget _buildRecycleBinSection(TaskProvider provider) {
    final l = context.l;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _isRecycleBinExpanded = !_isRecycleBinExpanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Colors.grey, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(l.isZh ? '回收站' : 'Recycle Bin',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_recentlyDeleted.length}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isRecycleBinExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.textHintColor, size: 24),
                  ),
                ],
              ),
            ),
          ),
          if (_isRecycleBinExpanded)
            Column(
              children: [
                ..._recentlyDeleted.take(20).map((task) => Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: Colors.grey[400]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                                decoration: TextDecoration.lineThrough,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _restoreFromRecycleBin(task.id, provider),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 28),
                            ),
                            child: Text(l.isZh ? '恢复' : 'Restore',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => setState(() =>
                                _recentlyDeleted.removeWhere(
                                    (t) => t.id == task.id)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: const Size(0, 28),
                            ),
                            child: Text(l.isZh ? '移除' : 'Dismiss',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    )),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    l.isZh ? '已删除的任务可通过「恢复」撤回' : 'Deleted tasks can be restored',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ),
              ],
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
    final completedTasks = provider.completedTasks
        .where((task) => !_undoableCompletedTasks.containsKey(task.id))
        .toList();

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
                    style: const TextStyle(
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
                  if (provider.archivedTasks.isNotEmpty)
                    IconButton(
                      tooltip: '归档箱',
                      onPressed: () => _showArchivedTasks(provider),
                      icon: Badge(
                        label: Text('${provider.archivedTasks.length}'),
                        child: const Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                  // 展开/收起图标
                  AnimatedRotation(
                    turns: _isCompletedExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textHintColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的任务列表（收起时不构建，避免全量渲染开销）
          if (_isCompletedExpanded)
            Column(
              children: [
                // 性能优化：已完成任务只渲染最近 20 个，避免全量渲染卡顿
                ...completedTasks.take(20).map((task) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                    child: TaskCard(
                      task: task,
                      onTap: () => _showTaskDetail(task),
                      isDistributed:
                          provider.distributedTaskIds.contains(task.id),
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
                }),
                // 超过 20 个时提示去全部任务页查看
                if (completedTasks.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: TextButton(
                      onPressed: () => setState(() => _currentIndex = 1),
                      child: Text(
                        l.isZh
                            ? '查看全部 ${completedTasks.length} 个已完成任务'
                            : 'View all ${completedTasks.length} completed tasks',
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _showArchivedTasks(TaskProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.7,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.inventory_2_outlined),
                title: Text('任务归档箱',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('归档任务保留全部内容，可随时恢复'),
              ),
              const Divider(height: 1),
              Expanded(
                child: Consumer<TaskProvider>(
                  builder: (_, currentProvider, __) => ListView.separated(
                    itemCount: currentProvider.archivedTasks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final task = currentProvider.archivedTasks[index];
                      return ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(task.title),
                        subtitle: Text(
                            '归档于 ${_formatDateTime(task.archivedAt ?? task.updatedAt)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '永久删除',
                              icon: const Icon(Icons.delete_forever_outlined),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: sheetContext,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('永久删除任务'),
                                    content:
                                        const Text('任务及其无引用附件将被永久删除，无法恢复。'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(
                                              dialogContext, false),
                                          child: const Text('取消')),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(
                                              dialogContext, true),
                                          child: const Text('永久删除')),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await currentProvider
                                      .permanentlyDeleteArchivedTask(task.id);
                                }
                              },
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  currentProvider.restoreArchivedTask(task.id),
                              icon: const Icon(Icons.restore_rounded),
                              label: const Text('恢复'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restoreTask(String id, TaskProvider provider) {
    final l = context.l;
    provider.restoreTask(id);
    setState(() => _undoableCompletedTasks.remove(id));
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

  /// 通知详情对话框：显示完整内容（不被列表的 2 行截断），并可跳转关联任务
  void _showNotificationDetail(
      Map<String, dynamic> n, void Function(VoidCallback) setInner) {
    final l = context.l;
    final read = n['read'] as bool? ?? false;
    final title = n['title'] as String? ?? '';
    final body = n['body'] as String? ?? '';
    final createdAt = n['createdAt'] as String? ?? '';
    final taskId = n['taskId'] as String?;
    final task = taskId == null
        ? null
        : context
            .read<TaskProvider>()
            .tasks
            .where((t) => t.id == taskId)
            .firstOrNull;
    final dt = DateTime.tryParse(createdAt);
    final createdAtText = dt != null ? _formatDateTime(dt) : createdAt;

    // 打开详情即标记已读
    if (!read) {
      BackendApiService.instance.markNotificationRead(n['id'] as String);
      _loadUnreadCount();
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 12),
              Text(createdAtText,
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textHintColor)),
            ],
          ),
        ),
        actions: [
          if (task != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                _showTaskDetail(task);
              },
              child: Text(l.viewTask),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (!read) setInner(() {});
            },
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _showNotificationCenter() {
    final l = context.l;
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
                      child: const Icon(Icons.notifications_active_rounded,
                          color: AppTheme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(l.notificationCenter,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await BackendApiService.instance
                            .markAllNotificationsRead();
                        if (!mounted || !context.mounted) return;
                        _loadUnreadCount();
                        Navigator.pop(context);
                      },
                      child: Text(l.markAllRead),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StatefulBuilder(builder: (context, setInner) {
                  final notifFuture =
                      BackendApiService.instance.getNotifications();
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: notifFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primaryColor));
                      }
                      if (snapshot.hasError) {
                        return ErrorStateWidget(
                          onRetry: () => setInner(() {}),
                        );
                      }
                      final notifications = snapshot.data ?? [];
                      if (notifications.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_off_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(l.noNotifications,
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 15)),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final n = notifications[index];
                          final read = n['read'] as bool? ?? false;
                          final title = n['title'] as String? ?? '';
                          final body = n['body'] as String? ?? '';
                          final type = n['type'] as String? ?? '';
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    (read ? Colors.grey : AppTheme.primaryColor)
                                        .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                type == 'mention'
                                    ? Icons.alternate_email_rounded
                                    : type == 'assignment'
                                        ? Icons.person_pin_rounded
                                        : type == 'distribution'
                                            ? Icons.send_rounded
                                            : Icons.info_outline,
                                size: 18,
                                color:
                                    read ? Colors.grey : AppTheme.primaryColor,
                              ),
                            ),
                            title: Text(title,
                                style: TextStyle(
                                    fontWeight: read
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                    fontSize: 14)),
                            subtitle: Text(body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                            trailing: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: read
                                    ? Colors.transparent
                                    : AppTheme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            onTap: () => _showNotificationDetail(n, setInner),
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
    final l = context.l;
    final nameFuture = _resolveUserName(task.assigneeUserId!);
    return FutureBuilder<String>(
      future: nameFuture,
      builder: (context, snapshot) {
        final name =
            snapshot.hasError ? l.unknown : (snapshot.data ?? l.loading);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 18, color: AppTheme.textSecondaryColor),
              const SizedBox(width: 8),
              Text(l.assignedTo,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondaryColor)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 14, color: AppTheme.primaryColor),
                    const SizedBox(width: 4),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                onPressed: () => _showAssignTaskDialog(task),
                tooltip: l.changeAssignee,
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
      final members = await BackendApiService.instance
          .getTeamMembers(teams.first['id'] as String);
      for (final m in members) {
        _userNameCache[m.userId] = m.displayName;
      }
      return _userNameCache[userId] ?? userId;
    } catch (_) {
      return userId;
    }
  }

  void _showAssignTaskDialog(Task task) {
    final l = context.l;
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
                    const Icon(Icons.person_add_rounded,
                        color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    Text(l.assignTask,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(height: 1),
              StatefulBuilder(
                builder: (context, setInner) {
                  return FutureBuilder<Map<String, dynamic>?>(
                    future: _loadTeamAndMembers(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppTheme.primaryColor)),
                        );
                      }
                      if (snapshot.hasError) {
                        // 对话框内为 mainAxisSize.min 的 Column，居中模式需有界高度，
                        // 故给定固定高度承载居中错误态。
                        return SizedBox(
                          height: 200,
                          child: ErrorStateWidget(
                            onRetry: () => setInner(() {}),
                          ),
                        );
                      }
                      final data = snapshot.data;
                      if (data == null) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(l.notInTeamCantAssign,
                              style: const TextStyle(
                                  color: AppTheme.textSecondaryColor)),
                        );
                      }
                      final members =
                          data['members'] as List<BackendTeamMember>;
                      final currentUserId = BackendApiService.instance.userId;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final m = members[index];
                          final isCurrentAssignee =
                              task.assigneeUserId == m.userId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isCurrentAssignee
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade300,
                              child: Text(
                                m.displayName.isNotEmpty
                                    ? m.displayName[0]
                                    : '?',
                                style: TextStyle(
                                    color: isCurrentAssignee
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                    fontSize: 14),
                              ),
                            ),
                            title: Text(m.displayName),
                            subtitle: m.userId == currentUserId
                                ? Text(l.self,
                                    style: const TextStyle(fontSize: 12))
                                : null,
                            trailing: isCurrentAssignee
                                ? const Icon(Icons.check_circle,
                                    color: AppTheme.primaryColor)
                                : null,
                            onTap: () {
                              final provider = context.read<TaskProvider>();
                              provider.updateTask(
                                  task.copyWith(assigneeUserId: m.userId));
                              Navigator.pop(context);
                            },
                          );
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

  Widget _buildDateRangeChip(
      String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
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
          color: hasValue
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: hasValue
              ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 14,
                color: hasValue ? AppTheme.primaryColor : Colors.grey[500]),
            const SizedBox(width: 4),
            Text(
              hasValue ? '${value.month}/${value.day}' : label,
              style: TextStyle(
                  fontSize: 12,
                  color: hasValue ? AppTheme.primaryColor : Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecentSearches(TaskProvider provider) {
    final l = context.l;
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
                Text(l.recentSearches,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                TextButton(
                  onPressed: () {
                    provider.clearRecentSearches();
                    Navigator.pop(context);
                  },
                  child: Text(l.clear),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: provider.recentSearches
                  .map((s) => ActionChip(
                        label: Text(s,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87)),
                        onPressed: () {
                          provider.setSearchQuery(s);
                          Navigator.pop(context);
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchToolbar(TaskProvider provider) {
    final l = context.l;
    final allTasks = _getFilteredTaskList(provider)
        .where((t) => t.parentId == null)
        .toList();
    final allSelected = allTasks.isNotEmpty &&
        allTasks.every((t) => _selectedTaskIds.contains(t.id));
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
          Text(l.selectedCount(_selectedTaskIds.length),
              style: const TextStyle(fontSize: 13)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 20),
            tooltip: l.batchMarkComplete,
            onPressed: _selectedTaskIds.isEmpty
                ? null
                : () async {
                    await provider.batchUpdateTasks(_selectedTaskIds.toList(),
                        status: TaskStatus.completed);
                    setState(() {
                      _selectedTaskIds.clear();
                    });
                  },
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_outline, size: 20),
            tooltip: l.batchStart,
            onPressed: _selectedTaskIds.isEmpty
                ? null
                : () async {
                    await provider.batchUpdateTasks(_selectedTaskIds.toList(),
                        status: TaskStatus.inProgress);
                    setState(() {
                      _selectedTaskIds.clear();
                    });
                  },
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined, size: 20),
            tooltip: '批量归档',
            onPressed: _selectedTaskIds.isEmpty
                ? null
                : () async {
                    await provider.batchArchiveTasks(_selectedTaskIds.toList());
                    setState(() {
                      _selectedTaskIds.clear();
                    });
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: l.batchDelete,
            onPressed: _selectedTaskIds.isEmpty
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(l.confirmDelete),
                        content:
                            Text(l.confirmBatchDelete(_selectedTaskIds.length)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(_, false),
                              child: Text(l.cancel)),
                          TextButton(
                              onPressed: () => Navigator.pop(_, true),
                              child: Text(l.delete)),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await provider
                          .batchDeleteTasks(_selectedTaskIds.toList());
                      setState(() {
                        _selectedTaskIds.clear();
                      });
                    }
                  },
          ),
        ],
      ),
    );
  }
}
