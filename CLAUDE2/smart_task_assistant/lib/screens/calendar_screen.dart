import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../screens/add_task_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final allTasks = provider.tasks;

        return Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TableCalendar<Task>(
                firstDay: DateTime(2024, 1, 1),
                lastDay: DateTime(2027, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() => _calendarFormat = format);
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                eventLoader: (day) {
                  return allTasks.where((t) {
                    final start = t.startTime;
                    final due = t.dueTime;
                    if (start != null && isSameDay(start, day)) return true;
                    if (due != null && isSameDay(due, day)) return true;
                    return false;
                  }).toList();
                },
                calendarBuilders: CalendarBuilders<Task>(
                  markerBuilder: (context, date, events) {
                    if (events.isEmpty) return null;
                    final colors = <Color>{
                      for (final t in events) _statusColor(t.status),
                    };
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final c in colors.take(3))
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  markerSizeScale: 0.2,
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                ),
                locale: 'zh_CN',
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildTaskList(context, allTasks)),
            _buildCalendarActions(context, allTasks),
          ],
        );
      },
    );
  }

  Widget _buildCalendarActions(BuildContext context, List<Task> allTasks) {
    final day = _selectedDay ?? _focusedDay;
    final unplanned = allTasks
        .where((task) => task.startTime == null && task.dueTime == null)
        .toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: unplanned.isEmpty
                    ? null
                    : () => _showUnplannedTasks(context, unplanned),
                icon: const Icon(Icons.inbox_outlined),
                label: Text('未安排 ${unplanned.length}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _createTaskForDay(context, day),
                icon: const Icon(Icons.add),
                label: const Text('新建任务'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _completedExpanded = false;

  Widget _buildTaskList(BuildContext context, List<Task> allTasks) {
    final provider = context.read<TaskProvider>();
    final day = _selectedDay ?? _focusedDay;
    final tasks = allTasks.where((t) {
      final start = t.startTime;
      final due = t.dueTime;
      if (start != null && isSameDay(start, day)) return true;
      if (due != null && isSameDay(due, day)) return true;
      return false;
    }).toList();

    final uncompleted = tasks.where((t) => !t.isCompleted).toList();
    final completed = tasks.where((t) => t.isCompleted).toList();

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('这天没有任务', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        if (uncompleted.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              '待完成 (${uncompleted.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
            ),
          ),
          ...uncompleted.map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TaskCard(
              task: task,
              subtaskDone: (provider.subtasksByParentId[task.id] ?? const []).where((t) => t.isCompleted).length,
              subtaskTotal: provider.subtasksByParentId[task.id]?.length,
              onTap: () => _showTaskDetail(task),
              isDistributed: provider.distributedTaskIds.contains(task.id),
              onComplete: () => _completeTask(task, provider),
              onDelete: () => _deleteTask(task, provider),
              onStart: () => _startTask(task, provider),
              onStatusChange: (status) => _changeStatus(task, status, provider),
              onPriorityChange: (p) => _changePriority(task, p, provider),
              onDueTimeTap: () => _showTaskDetail(task),
              onReminderTap: () => _showTaskDetail(task),
              onRecurringTap: () => _showTaskDetail(task),
              availableTags: _getAllTags(provider),
              onTagsChanged: (ids) => _updateTags(task, ids, provider),
            ),
          )),
        ],
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _completedExpanded = !_completedExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppTheme.successColor, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text('已完成', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${completed.length}', style: const TextStyle(fontSize: 12, color: AppTheme.successColor)),
                  ),
                  const Spacer(),
                  Icon(
                    _completedExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: completed.map((task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Opacity(
                  opacity: 0.6,
                  child: TaskCard(
                    task: task,
                    subtaskDone: (provider.subtasksByParentId[task.id] ?? const [])
                        .where((t) => t.isCompleted)
                        .length,
                    subtaskTotal: provider.subtasksByParentId[task.id]?.length,
                    onTap: () => _showTaskDetail(task),
                    isDistributed: provider.distributedTaskIds.contains(task.id),
                    onComplete: () => _restoreTask(task, provider),
                    onDelete: () => _deleteTask(task, provider),
                    onStatusChange: (status) => _changeStatus(task, status, provider),
                    onPriorityChange: (p) => _changePriority(task, p, provider),
                  ),
                ),
              )).toList(),
            ),
            crossFadeState: _completedExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ],
    );
  }

  List<Tag> _getAllTags(TaskProvider provider) {
    return Tag.getDefaultTags();
  }

  void _completeTask(Task task, TaskProvider provider) {
    provider.updateTaskStatus(task.id, TaskStatus.completed);
  }

  void _restoreTask(Task task, TaskProvider provider) {
    provider.updateTaskStatus(task.id, TaskStatus.pending);
  }

  void _deleteTask(Task task, TaskProvider provider) {
    provider.deleteTask(task.id);
  }

  void _startTask(Task task, TaskProvider provider) {
    provider.updateTaskStatus(task.id, TaskStatus.inProgress);
  }

  void _changeStatus(Task task, TaskStatus status, TaskProvider provider) {
    provider.updateTaskStatus(task.id, status);
  }

  void _changePriority(Task task, TaskPriority priority, TaskProvider provider) {
    provider.updateTask(task.copyWith(priority: priority));
  }

  void _updateTags(Task task, List<String> tagIds, TaskProvider provider) {
    provider.updateTask(task.copyWith(tagIds: tagIds));
  }

  void _showTaskDetail(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddTaskScreen(task: task)),
    );
  }

  void _createTaskForDay(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final initialDueTime = DateTime(day.year, day.month, day.day, now.hour, now.minute);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(initialDueTime: initialDueTime),
      ),
    );
  }

  void _showUnplannedTasks(BuildContext context, List<Task> tasks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return Container(
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '未安排任务',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TaskCard(
                          task: task,
                          compact: true,
                          onTap: () {
                            Navigator.pop(context);
                            _showTaskDetail(task);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.pending: return Colors.orange;
      case TaskStatus.inProgress: return Colors.blue;
      case TaskStatus.completed: return Colors.green;
      case TaskStatus.cancelled: return Colors.grey;
    }
  }
}
