import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
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
import 'add_task_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';

/// 主页面 - 互联网风格设计
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  String? _selectedFilter;
  late AnimationController _fabAnimationController;
  bool _isCompletedExpanded = false; // 已完成任务栏目展开状态

  // 时间和天气相关
  Timer? _timeTimer;
  String _currentTime = '';
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
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    // 强制刷新天气信息（不使用缓存，以获取最新位置）
    _forceRefreshWeather();
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    _timeTimer?.cancel();
    super.dispose();
  }

  /// 更新时间
  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    });
  }

  /// 加载天气信息
  Future<void> _loadWeather() async {
    if (_isLoadingWeather) return;

    setState(() {
      _isLoadingWeather = true;
    });

    try {
      // 使用getWeather（带缓存）或refreshWeather（强制刷新）
      final weather = await _weatherService.getWeather();
      setState(() {
        _weatherInfo = weather;
        _isLoadingWeather = false;
      });
    } catch (e) {
      debugPrint('加载天气失败: $e');
      setState(() {
        _isLoadingWeather = false;
      });
    }
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFAFAFA), // 非常浅的灰色，接近白色
              Color(0xFFF8F8F8), // 浅灰
              Color(0xFFF5F5F5), // 稍深的浅灰
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: _buildBody(),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _currentIndex == 0 ? _buildFAB() : null,
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildTodayPage();
      case 1:
        return _buildAllTasksPage();
      case 2:
        return const StatsScreen();
      case 3:
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getDateDescription(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimaryColor,
                              ),
                            ),
                            if (_currentTime.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 14,
                                      color: AppTheme.primaryColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _currentTime,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: [
                            _buildHeaderButton(
                              Icons.search_rounded,
                              () => setState(() => _currentIndex = 1),
                            ),
                            const SizedBox(width: 12),
                            _buildHeaderButton(
                              Icons.notifications_none_rounded,
                              () => _showNotifications(),
                              badge: provider.overdueTasks.isNotEmpty
                                  ? '${provider.overdueTasks.length}'
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 天气信息卡片
                    _buildWeatherCard(),
                    const SizedBox(height: 12),
                    // 进度卡片 - 紧凑版
                    _buildProgressCard(provider),
                  ],
                ),
              ),
            ),
            // AI 建议卡片
            if (provider.todayTasks.where((t) => !t.isCompleted).isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildAISuggestionCard(provider),
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            // 逾期任务横向列表
            if (provider.overdueTasks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: AppTheme.errorColor,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l.overdueTasks,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${provider.overdueTasks.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.errorColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: provider.overdueTasks.length,
                          itemBuilder: (context, index) {
                            final task = provider.overdueTasks[index];
                            return Container(
                              width: 280,
                              margin: EdgeInsets.only(
                                right: index == provider.overdueTasks.length - 1
                                    ? 0
                                    : 12,
                              ),
                              child: TaskCard(
                                task: task,
                                compact: true,
                                onTap: () => _showTaskDetail(task),
                                availableTags: _getAllTags(provider),
                                onTagsChanged: (tagIds) =>
                                    _updateTaskTags(task.id, tagIds, provider),
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
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            // 任务列表标题
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.pendingTasks,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _currentIndex = 1),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                      ),
                      child: Text(l.viewAll),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 12),
            ),
            // 待处理任务列表 - 只显示未完成的任务
            provider.todayTasks.where((t) => !t.isCompleted).isEmpty
                ? SliverToBoxAdapter(
                    child:
                        provider.todayTasks.where((t) => t.isCompleted).isEmpty
                            ? _buildEmptyState()
                            : const SizedBox.shrink(), // 如果只有已完成任务，不显示空状态
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final uncompletedTasks = provider.todayTasks
                              .where((t) => !t.isCompleted)
                              .toList();
                          final task = uncompletedTasks[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TaskCard(
                              task: task,
                              onTap: () => _showTaskDetail(task),
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
                          );
                        },
                        childCount: provider.todayTasks
                            .where((t) => !t.isCompleted)
                            .length,
                      ),
                    ),
                  ),
            // 已完成任务分组
            if (provider.todayTasks.where((t) => t.isCompleted).isNotEmpty)
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.9),
                                  Colors.white.withOpacity(0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
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
                                      prefixIcon:
                                          const Icon(Icons.search_rounded),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                if (provider.searchQuery.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () =>
                                        provider.setSearchQuery(''),
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
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _getFilteredTaskList(provider).isEmpty
                  ? SliverToBoxAdapter(
                      child: _buildEmptyState(isWhite: true),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = _getFilteredTaskList(provider)[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TaskCard(
                                task: task,
                                onTap: () => _showTaskDetail(task),
                                onComplete: () =>
                                    _completeTask(task.id, provider),
                                onDelete: () => _deleteTask(task.id, provider),
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
                                onTagsChanged: (tagIds) =>
                                    _updateTaskTags(task.id, tagIds, provider),
                              ),
                            );
                          },
                          childCount: _getFilteredTaskList(provider).length,
                        ),
                      ),
                    ),
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
              color: Colors.black.withOpacity(0.05),
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
                    color: AppTheme.primaryColor.withOpacity(0.3),
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

  Widget _buildEmptyState({bool isWhite = false}) {
    final l = context.l;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isWhite
                    ? AppTheme.primaryColor.withOpacity(0.1)
                    : Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.task_alt_rounded,
                size: 48,
                color: isWhite
                    ? AppTheme.primaryColor.withOpacity(0.5)
                    : Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.noTasks,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isWhite
                    ? AppTheme.textSecondaryColor
                    : Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.addTaskHint,
              style: TextStyle(
                color: isWhite
                    ? AppTheme.textHintColor
                    : Colors.white.withOpacity(0.7),
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.today_rounded, l.navToday),
              _buildNavItem(1, Icons.list_rounded, l.navAll),
              _buildNavItem(2, Icons.bar_chart_rounded, l.navStats),
              _buildNavItem(3, Icons.settings_rounded, l.navSettings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.1)
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
            color: const Color(0xFF667EEA).withOpacity(0.4),
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

  /// 构建天气卡片
  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.15),
            AppTheme.primaryColor.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // 天气图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getWeatherIcon(),
              size: 24,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          // 天气信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _showCitySelector,
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _weatherInfo?.cityName ?? '加载中...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_rounded,
                        size: 12,
                        color: AppTheme.textHintColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _weatherInfo?.temperatureText ?? '--°C',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _weatherInfo?.description ?? '天气信息',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 刷新按钮
          IconButton(
            icon: Icon(
              _isLoadingWeather ? Icons.refresh_rounded : Icons.refresh,
              size: 20,
              color: AppTheme.primaryColor,
            ),
            onPressed: _isLoadingWeather ? null : _forceRefreshWeather,
          ),
        ],
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
    final todayTasks = provider.todayTasks;
    final overdueTasks = provider.overdueTasks;

    final completedTasks = todayTasks.where((t) => t.isCompleted).toList();
    final inProgressTasks = todayTasks
        .where((t) => t.status == TaskStatus.inProgress && !t.isOverdue)
        .toList();
    final pendingTasks = todayTasks
        .where((t) =>
            t.status == TaskStatus.pending && !t.isCompleted && !t.isOverdue)
        .toList();

    final completedCount = completedTasks.length;
    final inProgressCount = inProgressTasks.length;
    final pendingCount = pendingTasks.length;
    final overdueCount = overdueTasks.length;
    final totalCount = todayTasks.length;
    final activeTotal =
        completedCount + inProgressCount + pendingCount + overdueCount;
    final progressPercent =
        activeTotal > 0 ? completedCount / activeTotal : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
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
            color: color.withOpacity(0.15),
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

  /// 构建AI建议卡片
  Widget _buildAISuggestionCard(TaskProvider provider) {
    final l = context.l;
    final uncompletedTasks =
        provider.todayTasks.where((t) => !t.isCompleted).toList();
    final highPriorityTasks =
        uncompletedTasks.where((t) => t.priority == TaskPriority.high).toList();
    final highPriorityTask =
        highPriorityTasks.isNotEmpty ? highPriorityTasks.first : null;

    String suggestion = '🎉 太棒了！今天没有待处理的任务，享受轻松时光吧！';
    if (highPriorityTask != null) {
      suggestion = '💡 建议优先处理「${highPriorityTask.title}」';
      if (highPriorityTask.dueTime != null) {
        suggestion += '，截止时间: ${highPriorityTask.dueTimeDescription}';
      }
      suggestion += '。';
    } else if (uncompletedTasks.isNotEmpty) {
      suggestion = '💡 建议处理「${uncompletedTasks.first.title}」';
      if (uncompletedTasks.first.dueTime != null) {
        suggestion += '，截止时间: ${uncompletedTasks.first.dueTimeDescription}';
      }
      suggestion += '。';
    }

    return GestureDetector(
      onTap: () => showAIChatDialog(context),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1).withOpacity(0.9),
              const Color(0xFF8B5CF6).withOpacity(0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.aiSuggestion,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final l = context.l;
    final hour = DateTime.now().hour;
    if (hour < 6) return l.greetingNight;
    if (hour < 12) return l.greetingMorning;
    if (hour < 14) return l.greetingNoon;
    if (hour < 18) return l.greetingAfternoon;
    return l.greetingEvening;
  }

  String _getDateDescription() {
    final l = context.l;
    final now = DateTime.now();
    if (l.isZh) {
      return '${now.year}年${now.month}月${now.day}日 · ${_getWeekday()}';
    } else {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[now.month - 1]} ${now.day}, ${now.year} · ${_getWeekday()}';
    }
  }

  String _getWeekday() {
    final l = context.l;
    if (l.isZh) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[DateTime.now().weekday - 1];
    } else {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[DateTime.now().weekday - 1];
    }
  }

  void _showNotifications() {
    final l = context.l;
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.errorColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l.overdueReminder,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Consumer<TaskProvider>(
                    builder: (context, provider, _) {
                      if (provider.overdueTasks.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(l.noOverdueTasks),
                          ),
                        );
                      }
                      return Column(
                        children: provider.overdueTasks.take(5).map((task) {
                          return ListTile(
                            leading: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.errorColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(task.title),
                            subtitle: Text(
                                '${l.deadline}: ${task.dueTimeDescription}'),
                            trailing: TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showTaskDetail(task);
                              },
                              child: Text(l.view),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
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
                                    .withOpacity(0.15),
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
                                    .withOpacity(0.15),
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
                        const SizedBox(height: 24),
                        _buildStatusSelector(task),
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
            color: isSelected ? color.withOpacity(0.15) : Colors.white,
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
    final task = provider.tasks.firstWhere((t) => t.id == taskId,
        orElse: () => throw Exception('Task not found'));
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
                          child: Text(l.noReminder),
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
                                ? AppTheme.primaryColor.withOpacity(0.15)
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
                                ? AppTheme.primaryColor.withOpacity(0.15)
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
    final task = provider.tasks.firstWhere((t) => t.id == taskId,
        orElse: () => throw Exception('Task not found'));
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final l = context.l;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
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
    final task = provider.tasks.firstWhere((t) => t.id == id,
        orElse: () => throw Exception('Task not found'));
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
    final completedTasks =
        provider.todayTasks.where((t) => t.isCompleted).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                      color: AppTheme.successColor.withOpacity(0.15),
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
                      color: AppTheme.successColor.withOpacity(0.15),
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
    final defaultTags = [
      Tag(id: 'default_work', name: '工作', color: '#3B82F6', isDefault: true),
      Tag(
          id: 'default_personal',
          name: '个人',
          color: '#10B981',
          isDefault: true),
      Tag(id: 'default_urgent', name: '紧急', color: '#EF4444', isDefault: true),
      Tag(id: 'default_study', name: '学习', color: '#8B5CF6', isDefault: true),
    ];

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
    if (_selectedFilter == 'overdue') {
      return provider.overdueTasks;
    }
    return provider.filteredTasks;
  }
}
