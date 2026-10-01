import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/database_helper.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../theme/app_theme.dart';
import 'package:uuid/uuid.dart';

/// 专注模式（番茄钟）：选一个任务开始专注倒计时，
/// 结束自动记录会话（focus_sessions 表），可选择完成任务。
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  static const List<int> _durationOptions = [25, 45, 60];

  Task? _selectedTask;
  int _selectedMinutes = 25;
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _running = false;
  DateTime? _startedAt;
  DateTime? _deadlineAt; // 墙钟截止时刻：后台 Timer 冻结时据此校准

  @override
  void dispose() {
    _timer?.cancel();
    // 专注进行中直接退出页面：会话按已进行时长落库（incomplete），不丢数据
    if (_running && _startedAt != null) {
      final elapsed =
          DateTime.now().difference(_startedAt!).inMinutes;
      DatabaseHelper().saveFocusSession(
        id: const Uuid().v4(),
        taskId: _selectedTask?.id,
        taskTitle: _selectedTask?.title,
        startedAt: _startedAt!,
        endedAt: DateTime.now(),
        durationMinutes: elapsed <= 0 ? 1 : elapsed,
        completed: false,
      );
    }
    super.dispose();
  }

  Future<void> _start() async {
    final deadline = DateTime.now().add(Duration(minutes: _selectedMinutes));
    setState(() {
      _remainingSeconds = _selectedMinutes * 60;
      _running = true;
      _startedAt = DateTime.now();
      _deadlineAt = deadline;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      // 以墙钟校准：退后台 Timer 冻结后回来自动追平
      final remaining = _deadlineAt!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        await _finish(completed: true);
      } else {
        setState(() => _remainingSeconds = remaining);
      }
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _finish(completed: false);
  }

  Future<void> _finish({required bool completed}) async {
    _timer?.cancel();
    final startedAt = _startedAt ?? DateTime.now();
    // 会话时长按墙钟计算（而非剩余秒数），后台冻结不会失真
    final elapsed = DateTime.now().difference(startedAt).inMinutes;
    try {
      await DatabaseHelper().saveFocusSession(
        id: const Uuid().v4(),
        taskId: _selectedTask?.id,
        taskTitle: _selectedTask?.title,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        durationMinutes: elapsed <= 0 ? 1 : elapsed,
        completed: completed,
      );
    } catch (_) {
      // 历史记录失败不影响主流程
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _remainingSeconds = 0;
      _startedAt = null;
      _deadlineAt = null;
    });

    if (completed) {
      final markDone = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('专注完成！🎉'),
          content: Text(_selectedTask == null
              ? '已专注 $_selectedMinutes 分钟，休息一下吧。'
              : '已专注 $_selectedMinutes 分钟。要把「${_selectedTask!.title}」标记为完成吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('暂不')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('标记完成')),
          ],
        ),
      );
      if (markDone == true && _selectedTask != null && mounted) {
        await context.read<TaskProvider>().completeTask(_selectedTask!.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('专注会话已记录'), duration: Duration(seconds: 2)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('专注已中断，会话已记录')),
      );
    }
  }

  String _formatRemaining() {
    final m = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    var candidates = provider.tasks
        .where((t) => !t.isCompleted && t.status != TaskStatus.cancelled)
        .toList();
    // 所选任务在专注期间被完成/移出候选时，仍保留为选项，避免 value 悬空崩溃
    final selected = _selectedTask;
    if (selected != null && candidates.every((t) => t.id != selected.id)) {
      candidates = [selected, ...candidates];
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('专注模式')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 任务选择
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Task?>(
                    value: _selectedTask,
                    isExpanded: true,
                    hint: const Text('选择要专注的任务（可不选）',
                        style: TextStyle(fontSize: 14)),
                    items: candidates
                        .take(50)
                        .map((t) => DropdownMenuItem<Task?>(
                              value: t,
                              child: Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)),
                            ))
                        .toList(),
                    onChanged: _running
                        ? null
                        : (t) => setState(() => _selectedTask = t),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 时长选择
              if (!_running)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _durationOptions
                      .map((m) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ChoiceChip(
                              label: Text('$m 分钟'),
                              selected: _selectedMinutes == m,
                              onSelected: (_) =>
                                  setState(() => _selectedMinutes = m),
                            ),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 24),
              // 倒计时
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_selectedTask != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _selectedTask!.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      Text(
                        _running || _remainingSeconds > 0
                            ? _formatRemaining()
                            : '$_selectedMinutes:00',
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w800,
                          color: _running
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _running ? '专注中，别被打扰哦' : '选择任务和时长，开始专注',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondaryColor),
                      ),
                    ],
                  ),
                ),
              ),
              // 操作按钮
              Row(
                children: [
                  if (_running) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _stop,
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('结束专注'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorColor,
                          side: const BorderSide(color: AppTheme.errorColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('开始专注'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
