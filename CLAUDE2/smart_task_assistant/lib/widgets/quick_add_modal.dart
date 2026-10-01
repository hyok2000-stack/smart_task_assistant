import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/ocr_service.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../services/ai_service.dart';
import '../services/speech_input_service.dart';
import '../services/task_parse_controller.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import 'ocr_source_sheet.dart';
import 'tag_create_dialog.dart';

/// 可拖动的快速创建任务对话框
class QuickAddModal extends StatefulWidget {
  final String? initialContent;

  const QuickAddModal({super.key, this.initialContent});

  @override
  State<QuickAddModal> createState() => _QuickAddModalState();
}

class _QuickAddModalState extends State<QuickAddModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _aiService = AIService();
  final bool _isLoading = false;
  bool _isAILoading = false;
  bool _isOcrProcessing = false;
  bool _isListening = false;
  ParsedTask? _parsedTask;
  // 解析出的标题（用户可在预览中修正），为空时回退到 parsed.title
  String? _editableTitle;

  // 可编辑的任务属性
  TaskPriority _selectedPriority = TaskPriority.medium;
  DateTime? _selectedDueTime;
  int? _selectedReminderMinutes = 10; // 提前提醒时间（默认10分钟）
  bool _reminderVoiceEnabled = true; // 默认启用语音提醒
  List<String> _selectedTags = ['工作'];
  bool _isCreating = false;

  // 自定义提醒时间
  int? _customReminderMinutes;
  bool _showCustomReminder = false;

  // 周期任务
  bool _isRecurring = false;
  String _recurringRule = 'daily'; // daily, weekly, monthly, yearly

  // 语音可用性预检：null=检测中，false=系统识别与离线识别都不可用（按钮置灰）
  bool? _speechSupported;

  @override
  void initState() {
    super.initState();

    // 异步预检语音可用性（两级引擎：系统 ASR → 离线模型；
    // 同时预热离线引擎，故障切换时即时可用）
    SpeechInputService.instance.ensureInitialized().then((systemOk) async {
      if (systemOk) {
        if (mounted) setState(() => _speechSupported = true);
        // 后台预热离线引擎（系统识别不可靠时即时切换）
        await SpeechInputService.instance.ensureOfflineReady();
        return;
      }
      final offlineOk = await SpeechInputService.instance.ensureOfflineReady();
      if (mounted) setState(() => _speechSupported = offlineOk);
    });

    // 如果有初始内容，设置到输入框并自动解析
    if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
      _controller.text = widget.initialContent!;
      // 延迟解析，确保组件已构建完成
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _parseInputAuto(widget.initialContent!);
      });
    }
  }

  @override
  void dispose() {
    // 弹窗关闭时若仍在聆听，立即停麦（隐私敏感：不允许后台持续拾音）
    if (_isListening) {
      SpeechInputService.instance.stopListening();
      _isListening = false;
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 自动解析输入（优先使用AI，失败回退到本地规则）
  Future<void> _parseInputAuto(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _parsedTask = null);
      return;
    }

    setState(() => _isAILoading = true);

    try {
      // AI 优先解析（未配置/失败自动回退本地规则，见 TaskParseController）
      final result = await TaskParseController.parseWithEngine(input);

      if (result != null && mounted) {
        final s = TaskParseController.resolve(result);
        setState(() {
          _parsedTask = result;
          _selectedPriority = s.priority;
          _selectedDueTime = s.dueTime;
          _selectedTags = s.tags;
          // 应用推荐的提醒时间（不在预设内时展开自定义输入框）
          if (s.reminderMinutes != null) {
            _selectedReminderMinutes = s.reminderMinutes;
            _showCustomReminder = s.showCustomReminder;
            if (s.showCustomReminder) {
              _customReminderMinutes = s.customReminderMinutes;
            }
          }
        });
      } else {
        // AI 解析失败，回退到本地规则
        _parseInputLocal(input);
      }
    } catch (e) {
      // AI 解析失败，回退到本地规则
      _parseInputLocal(input);
    } finally {
      if (mounted) {
        setState(() => _isAILoading = false);
      }
    }
  }

  /// 使用本地规则解析输入（手动调用）
  void _parseInputLocal(String input) {
    if (input.trim().isEmpty) {
      setState(() => _parsedTask = null);
      return;
    }

    // 使用本地规则引擎解析
    final result = _aiService.parseTaskLocal(input);
    final s = TaskParseController.resolve(result);
    setState(() {
      _parsedTask = result;
      // 自动更新选择器的值
      _selectedPriority = s.priority;
      _selectedDueTime = s.dueTime;
      _selectedTags = s.tags;
      // 应用推荐的提醒时间（不在预设内时展开自定义输入框）
      if (s.reminderMinutes != null) {
        _selectedReminderMinutes = s.reminderMinutes;
        _showCustomReminder = s.showCustomReminder;
        if (s.showCustomReminder) {
          _customReminderMinutes = s.customReminderMinutes;
        }
      }
        });
  }

  /// 使用AI智能识别（手动调用）
  Future<void> _parseInputWithAI() async {
    if (_controller.text.trim().isEmpty) return;

    setState(() => _isAILoading = true);
    try {
      final result = await TaskParseController.parseWithEngine(
        _controller.text,
      );
      if (result != null && mounted) {
        final s = TaskParseController.resolve(result);
        setState(() {
          _parsedTask = result;
          _selectedPriority = s.priority;
          _selectedDueTime = s.dueTime;
          _selectedTags = s.tags;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isAILoading = false);
      }
    }
  }

  Future<void> _selectDueTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDueTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDueTime ?? now),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          );
        },
      );

      if (time != null) {
        setState(() {
          _selectedDueTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _createTask() async {
    if (_controller.text.trim().isEmpty || _isCreating) return;

    if (_selectedDueTime == null) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('未设置截止日期'),
          content: const Text('设置截止日期后，应用可以更准确地安排提醒和任务进度。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('返回编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('仍然创建'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.event_outlined),
              label: const Text('设置截止日期'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice) {
        await _selectDueTime();
        if (!mounted || _selectedDueTime == null) return;
      }
    }

    setState(() => _isCreating = true);

    try {
      // 如果没有解析过，先用本地规则解析
      _parsedTask ??= _aiService.parseTaskLocal(_controller.text);

      final parsed = _parsedTask!;

      // 使用用户选择的优先级和截止时间。
      // 不再静默默认 +24h：无截止时间时存 null，让任务作为「无期限待办」存在，
      // 避免用户不知情地给所有任务强加截止时间（用户可在弹窗内主动设置）。
      final dueTime = _selectedDueTime;

      final task = Task(
        id: const Uuid().v4(),
        title: (_editableTitle?.isNotEmpty == true)
            ? _editableTitle!
            : parsed.title,
        content: _controller.text,
        dueTime: dueTime,
        priority: _selectedPriority,
        status: TaskStatus.pending,
        isRecurring: _isRecurring,
        recurringRule: _isRecurring ? _recurringRule : null,
        reminderMinutes: _selectedReminderMinutes,
        reminderVoiceEnabled: _reminderVoiceEnabled,
        reminderVoiceType: 'female',
        reminderVoiceStyle: 'lively',
        reminderVoiceSpeed: 'normal',
        sourceType: 'local',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final provider = context.read<TaskProvider>();

      // 收集所有标签ID（包括默认标签、自定义标签和新创建的标签）
      final tagIds = <String>[];

      // 包含默认标签
      final defaultTags = Tag.getDefaultTags();

      // 处理标签：找到对应的ID或创建新标签
      for (final tagName in _selectedTags) {
        if (tagName.trim().isEmpty) continue;

        Tag? tag;

        // 先在默认标签中查找
        try {
          tag = defaultTags.firstWhere(
            (t) => t.name.toLowerCase() == tagName.trim().toLowerCase(),
          );
        } catch (e) {
          tag = null;
        }

        // 如果找到默认标签，直接添加
        if (tag != null) {
          tagIds.add(tag.id);
          continue;
        }

        // 在自定义标签中查找
        try {
          tag = provider.tags.firstWhere(
            (t) => t.name.toLowerCase() == tagName.trim().toLowerCase(),
          );
        } catch (e) {
          tag = null;
        }

        if (tag != null) {
          tagIds.add(tag.id);
        } else {
          // 创建新标签
          final newTag = Tag(
            id: const Uuid().v4(),
            name: tagName.trim(),
            color: _getRandomTagColor(),
          );
          await provider.addTag(newTag);
          tagIds.add(newTag.id);
        }
      }

      // 将标签ID关联到任务
      final taskWithTags = task.copyWith(tagIds: tagIds);
      await provider.addTask(taskWithTags);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('任务「${parsed.title}」创建成功')),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  String _getRandomTagColor() {
    final colors = [
      '#6366F1',
      '#8B5CF6',
      '#EC4899',
      '#EF4444',
      '#F59E0B',
      '#10B981',
      '#06B6D4',
      '#3B82F6',
    ];
    return colors[Random().nextInt(colors.length)];
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 500 ? 480.0 : size.width * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: dialogWidth,
            constraints: BoxConstraints(
              maxHeight: size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 可拖动的标题栏
                _buildDraggableHeader(),
                // 内容区域
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 输入框（带拍照识别按钮）
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  onChanged: _parseInputLocal,
                                  maxLines: 3,
                                  minLines: 1,
                                  decoration: const InputDecoration(
                                    hintText: '例如：明天下午3点开会，比较紧急 #工作',
                                    hintStyle: TextStyle(
                                      color: AppTheme.textHintColor,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ),
                              // 拍照识别文本（OCR）
                              Padding(
                                padding: const EdgeInsets.only(
                                    right: 8, bottom: 8),
                                child: _isOcrProcessing
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : IconButton(
                                        tooltip: '拍照识别文本',
                                        icon: const Icon(
                                            Icons.camera_alt_outlined,
                                            size: 22),
                                        color: AppTheme.primaryColor,
                                        onPressed: _showOcrSourcePicker,
                                      ),
                              ),
                              // 语音输入（口述任务，走 AI 解析链）；
                              // 设备无识别服务时置灰，提示用输入法语音替代
                              Padding(
                                padding:
                                    const EdgeInsets.only(right: 8, bottom: 8),
                                child: Tooltip(
                                  message: _speechSupported == false
                                      ? '此设备无系统语音识别（可用输入法语音键替代）'
                                      : (_isListening ? '停止语音' : '语音输入'),
                                  child: IconButton(
                                    icon: _isListening
                                        ? const Icon(Icons.mic_rounded,
                                            size: 24)
                                        : const Icon(Icons.mic_none_rounded,
                                            size: 22),
                                    color: _isListening
                                        ? AppTheme.errorColor
                                        : AppTheme.primaryColor,
                                    disabledColor: Colors.grey.shade400,
                                    onPressed: _speechSupported == false
                                        ? null
                                        : _toggleSpeechInput,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 优先级和截止时间选择
                        Row(
                          children: [
                            // 优先级选择
                            SizedBox(
                              width: 120,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.grey.shade200),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<TaskPriority>(
                                    value: _selectedPriority,
                                    isExpanded: true,
                                    icon: Icon(Icons.expand_more,
                                        color: Colors.grey.shade600),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textPrimaryColor,
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: TaskPriority.high,
                                        child: Row(
                                          children: [
                                            Icon(Icons.flag,
                                                size: 16,
                                                color: AppTheme.errorColor),
                                            SizedBox(width: 8),
                                            Text('高优先级'),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: TaskPriority.medium,
                                        child: Row(
                                          children: [
                                            Icon(Icons.flag,
                                                size: 16,
                                                color: AppTheme.warningColor),
                                            SizedBox(width: 8),
                                            Text('中优先级'),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: TaskPriority.low,
                                        child: Row(
                                          children: [
                                            Icon(Icons.flag,
                                                size: 16,
                                                color: AppTheme.successColor),
                                            SizedBox(width: 8),
                                            Text('低优先级'),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(
                                            () => _selectedPriority = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 截止时间选择
                            Expanded(
                              child: GestureDetector(
                                onTap: _selectDueTime,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: _selectedDueTime != null
                                        ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedDueTime != null
                                          ? AppTheme.primaryColor
                                              .withValues(alpha: 0.3)
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                        color: _selectedDueTime != null
                                            ? AppTheme.primaryColor
                                            : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedDueTime != null
                                              ? _formatDateTime(
                                                  _selectedDueTime!)
                                              : '截止时间',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _selectedDueTime != null
                                                ? AppTheme.primaryColor
                                                : AppTheme.textHintColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (_selectedDueTime != null)
                                        GestureDetector(
                                          onTap: () => setState(
                                              () => _selectedDueTime = null),
                                          child: Icon(Icons.clear,
                                              size: 16,
                                              color: Colors.grey.shade600),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 提醒时间选择
                        const SizedBox(height: 16),
                        _buildReminderSelector(),
                        // 语音提醒开关（仅在选择了提醒时间时显示）
                        if (_selectedReminderMinutes != null) ...[
                          const SizedBox(height: 16),
                          _buildVoiceReminderToggle(),
                        ],
                        // 标签选择区域
                        const SizedBox(height: 16),
                        _buildTagSelector(),

                        // 已选标签显示
                        if (_selectedTags.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedTags.map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        AppTheme.primaryColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.label,
                                        size: 14, color: AppTheme.primaryColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      tag,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedTags.remove(tag);
                                        });
                                      },
                                      child: const Icon(Icons.close,
                                          size: 14,
                                          color: AppTheme.primaryColor),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        // 周期任务选择
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isRecurring
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isRecurring
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.repeat_rounded,
                                    size: 18,
                                    color: _isRecurring
                                        ? const Color(0xFF8B5CF6)
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '周期任务',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _isRecurring,
                                    onChanged: (value) {
                                      setState(() => _isRecurring = value);
                                    },
                                    activeThumbColor: const Color(0xFF8B5CF6),
                                  ),
                                ],
                              ),
                              if (_isRecurring) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _buildRecurringChip('每天', 'daily'),
                                    _buildRecurringChip('每周', 'weekly'),
                                    _buildRecurringChip('每月', 'monthly'),
                                    _buildRecurringChip('每年', 'yearly'),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // AI 识别按钮
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _isAILoading ? null : _parseInputWithAI,
                                  icon: _isAILoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.auto_awesome,
                                          size: 18),
                                  label: Text(
                                      _isAILoading ? 'AI识别中...' : 'AI智能识别'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF6366F1),
                                    side: const BorderSide(
                                        color: Color(0xFF6366F1)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 解析结果预览
                        if (_parsedTask != null) ...[
                          const SizedBox(height: 16),
                          _buildParsedPreview(),
                        ],
                        const SizedBox(height: 24),
                        // 按钮
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppTheme.primaryColor,
                                      AppTheme.primaryColor.withValues(alpha: 0.8),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton.icon(
                                  onPressed: _isCreating ? null : _createTask,
                                  icon: const Icon(Icons.add_task, size: 18),
                                  label: const Text('创建任务'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建语音提醒开关
  Widget _buildVoiceReminderToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _reminderVoiceEnabled
            ? AppTheme.primaryColor.withValues(alpha: 0.08)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _reminderVoiceEnabled
              ? AppTheme.primaryColor.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _reminderVoiceEnabled
                  ? AppTheme.primaryColor.withValues(alpha: 0.15)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _reminderVoiceEnabled
                  ? Icons.record_voice_over
                  : Icons.voice_over_off,
              size: 18,
              color: _reminderVoiceEnabled
                  ? AppTheme.primaryColor
                  : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '语音提醒',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _reminderVoiceEnabled
                        ? AppTheme.textPrimaryColor
                        : AppTheme.textHintColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _reminderVoiceEnabled ? '提醒时播放语音播报' : '未启用',
                  style: TextStyle(
                    fontSize: 12,
                    color: _reminderVoiceEnabled
                        ? AppTheme.primaryColor
                        : AppTheme.textHintColor,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _reminderVoiceEnabled,
            onChanged: (value) {
              setState(() => _reminderVoiceEnabled = value);
            },
            activeThumbColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  /// 构建提醒时间选择器
  Widget _buildReminderSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_none,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              const Text(
                '提前提醒',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 使用 Wrap 布局，自动换行
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildReminderChip('不提醒', null),
              _buildReminderChip('提前10分钟', 10),
              _buildReminderChip('提前15分钟', 15),
              _buildReminderChip('提前30分钟', 30),
              _buildReminderChip('提前1小时', 60),
              _buildReminderChip('提前1天', 1440),
              _buildReminderChip('自定义', -1),
            ],
          ),
          // 自定义输入区域
          if (_showCustomReminder) ...[
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '请输入分钟数',
                hintStyle:
                    const TextStyle(fontSize: 13, color: AppTheme.textHintColor),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixText: '分钟',
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) {
                final minutes = int.tryParse(value);
                if (minutes != null && minutes > 0) {
                  setState(() {
                    _customReminderMinutes = minutes;
                    _selectedReminderMinutes = minutes;
                  });
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 构建提醒时间芯片
  Widget _buildReminderChip(String label, int? minutes) {
    bool isSelected;
    if (minutes == -1) {
      // "自定义"选项
      isSelected = _showCustomReminder;
    } else if (minutes == null) {
      // "不提醒"选项
      isSelected = _selectedReminderMinutes == null && !_showCustomReminder;
    } else {
      isSelected = _selectedReminderMinutes == minutes && !_showCustomReminder;
    }

    // 检查是否是推荐的提醒时间
    final isRecommended = minutes != null &&
        minutes == _parsedTask?.recommendedReminderMinutes &&
        !_showCustomReminder;

    // 推荐项使用主色，其他使用警告色
    final chipColor =
        isRecommended ? AppTheme.primaryColor : AppTheme.warningColor;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (minutes == -1) {
            // 点击"自定义"
            _showCustomReminder = true;
            // 如果已有自定义时间，保持它
            if (_customReminderMinutes != null) {
              _selectedReminderMinutes = _customReminderMinutes;
            }
          } else {
            _showCustomReminder = false;
            _selectedReminderMinutes = minutes;
            if (minutes != null) {
              _customReminderMinutes = null;
            }
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor
              : chipColor.withValues(alpha: isRecommended ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor
                : chipColor.withValues(alpha: isRecommended ? 0.5 : 0.3),
            width: isRecommended && !isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecommended && !isSelected)
              Icon(
                Icons.auto_awesome,
                size: 12,
                color: chipColor,
              )
            else
              Icon(
                isSelected ? Icons.check : Icons.notifications_outlined,
                size: 14,
                color: isSelected ? Colors.white : AppTheme.textPrimaryColor,
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.white
                    : (isRecommended ? chipColor : AppTheme.textPrimaryColor),
                fontWeight: isRecommended ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (isRecommended && !isSelected) ...[
              const SizedBox(width: 4),
              Text(
                '推荐',
                style: TextStyle(
                  fontSize: 12,
                  color: chipColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor,
            AppTheme.primaryColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快速创建',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '输入任务内容，自动识别时间和优先级',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // 关闭按钮
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑解析出的标题（AI 解析出错时用户可修正）。
  /// 选择 OCR 图片来源（拍照 / 相册）
  Future<void> _showOcrSourcePicker() async {
    final fromCamera = await showOcrSourcePicker(context);
    if (fromCamera != null && mounted) {
      await _performOcr(fromCamera: fromCamera);
    }
  }

  /// 语音输入：口述任务内容 → 文字填入输入框 → 本地规则解析。
  /// 再次点击停止聆听（以最终识别结果触发一次解析）。
  /// 双引擎：系统 ASR 可用走系统识别；系统识别卡死/无响应自动切离线引擎。
  Future<void> _toggleSpeechInput() async {
    // 守卫用本地状态而非插件态：异步初始化/授权期间快速连点不会双开聆听
    if (_isListening || SpeechInputService.instance.isListening) {
      await SpeechInputService.instance.stopListening();
      await SpeechInputService.instance.stopOfflineListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    // 系统 ASR 已被判定不可靠（本次会话曾无结果）→ 直接走离线引擎
    if (SpeechInputService.instance.systemAsrUnreliable ||
        _speechSupported == false) {
      await _toggleOfflineInput();
      return;
    }

    final ok = await SpeechInputService.instance.ensureInitialized();
    if (!ok) {
      // 系统识别不可用 → 离线引擎
      await _toggleOfflineInput();
      return;
    }
    // 麦克风运行时权限（首次会弹系统授权）
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('麦克风权限已被拒绝，请到系统设置中开启')),
        );
        openAppSettings();
      }
      return;
    }
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能使用语音输入')),
        );
      }
      return;
    }

    // 清掉可能卡死的旧会话（华为识别服务的会话可能永不超时，
    // 不清理则后续 startListening 全部被 "in progress" 拒绝）
    await SpeechInputService.instance.stopListening();

    setState(() => _isListening = true);
    final baseText = _controller.text;
    var gotText = false;
    await SpeechInputService.instance.startListening(
      onResult: (text) {
        if (!mounted) return;
        if (text.trim().isNotEmpty) gotText = true;
        // 实时把识别内容追加到已有输入后面
        setState(() {
          _controller.text =
              baseText.isEmpty ? text : '$baseText $text'.trim();
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
      onFinal: (finalText) {
        if (!mounted) return;
        setState(() => _isListening = false);
        if (finalText.trim().isEmpty) {
          // 聆听了但零结果：系统引擎不可靠，标记后切离线引擎
          SpeechInputService.instance.systemAsrUnreliable = true;
          _toggleOfflineInput();
          return;
        }
        final full =
            baseText.isEmpty ? finalText : '$baseText $finalText'.trim();
        if (full.isNotEmpty) _parseInputLocal(full);
      },
      onStopped: () {
        // 引擎停止：有文字则已处理；无文字（卡死会话被清）标记不可靠
        if (!mounted) return;
        if (_isListening && !gotText) {
          SpeechInputService.instance.systemAsrUnreliable = true;
          debugPrint('系统 ASR 会话无结果，已标记为不可靠，后续走离线引擎');
        }
        if (_isListening) setState(() => _isListening = false);
      },
      onError: (message) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );
  }

  /// 离线引擎语音路径（sherpa-onnx 流式 zipformer，完全本地）
  Future<void> _toggleOfflineInput() async {
    if (_isListening) {
      final finalText =
          await SpeechInputService.instance.stopOfflineListening();
      if (mounted) setState(() => _isListening = false);
      final full = _controller.text.trim();
      if (full.isNotEmpty) _parseInputLocal(full);
      return;
    }

    final ready = await SpeechInputService.instance.ensureOfflineReady();
    if (!ready) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('离线语音模型初始化失败，请重试')),
        );
      }
      return;
    }
    // 麦克风运行时权限
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('麦克风权限已被拒绝，请到系统设置中开启')),
        );
        openAppSettings();
      }
      return;
    }
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能使用语音输入')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    final baseText = _controller.text;
    await SpeechInputService.instance.startOfflineListening(
      onText: (text) {
        if (!mounted) return;
        setState(() {
          _controller.text =
              baseText.isEmpty ? text : '$baseText $text'.trim();
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
      onDone: (finalText) {
        // 停止聆听：以最终文本重填输入框并触发解析
        if (!mounted) return;
        setState(() => _isListening = false);
        final full = baseText.isEmpty
            ? finalText.trim()
            : '$baseText ${finalText.trim()}'.trim();
        if (full.isNotEmpty) _parseInputLocal(full);
      },
    );
  }

  /// 执行 OCR 识别：结果填入输入框并触发本地解析（自动提取时间/优先级/标签）
  Future<void> _performOcr({required bool fromCamera}) async {
    setState(() => _isOcrProcessing = true);
    try {
      final text = fromCamera
          ? await OcrService.instance.captureAndRecognize()
          : await OcrService.instance.pickAndRecognize();

      if (!mounted) return;

      if (text == null || text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未识别到文字，请重试'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      setState(() {
        _controller.text = text;
        _editableTitle = null; // 清除旧的手动修正
      });
      // AI 优先解析（未配置/失败自动回退本地规则），提取标题/时间/优先级/标签
      // _parseInputWithAI 读取 _controller.text（已在上面填入 OCR 文字）
      await _parseInputWithAI();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_aiService.config.enabled
              ? 'AI 解析完成，请检查并编辑'
              : '识别完成（规则解析），请检查并编辑'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  Future<void> _editParsedTitle(String original) async {
    final controller = TextEditingController(text: _editableTitle ?? original);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改任务标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _editableTitle = result);
    }
  }

  Widget _buildParsedPreview() {
    final parsed = _parsedTask!;
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                '识别结果',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.successColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 标题
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.title_rounded,
                    size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _editableTitle ?? parsed.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // 编辑解析标题（AI 解析出错时用户可修正）
                GestureDetector(
                  onTap: () => _editParsedTitle(parsed.title),
                  child: Icon(Icons.edit_outlined,
                      size: 16, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 属性标签
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_selectedDueTime != null)
                _buildPreviewChip(
                  Icons.access_time_rounded,
                  _formatDateTime(_selectedDueTime!),
                  AppTheme.infoColor,
                ),
              _buildPreviewChip(
                Icons.flag_rounded,
                _getPriorityText(_selectedPriority),
                _getPriorityColor(_selectedPriority),
              ),
              if (_selectedReminderMinutes != null)
                _buildPreviewChip(
                  Icons.notifications_rounded,
                  '提前$_selectedReminderMinutes分钟',
                  AppTheme.warningColor,
                ),
              for (final tag in _selectedTags)
                _buildPreviewChip(
                    Icons.label_outline, tag, AppTheme.primaryColor),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    String dateStr;
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      dateStr = '今天';
    } else if (dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day) {
      dateStr = '明天';
    } else {
      dateStr = '${dt.month}月${dt.day}日';
    }

    return '$dateStr ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _getPriorityText(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return '高优先级';
      case TaskPriority.medium:
        return '中优先级';
      case TaskPriority.low:
        return '低优先级';
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

  Widget _buildPreviewChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringChip(String label, String rule) {
    final isSelected = _recurringRule == rule;
    return GestureDetector(
      onTap: () => setState(() => _recurringRule = rule),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF8B5CF6)
              : const Color(0xFF8B5CF6).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withValues(alpha: isSelected ? 1 : 0.3),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textPrimaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 构建标签选择器
  Widget _buildTagSelector() {
    return Consumer<TaskProvider>(
      builder: (context, provider, child) {
        // 获取默认标签
        final defaultTags = Tag.getDefaultTags();

        // 合并默认标签和自定义标签（去重）
        final allTags = [...defaultTags];
        for (final tag in provider.tags) {
          if (!defaultTags.any((t) => t.id == tag.id)) {
            allTags.add(tag);
          }
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.label_outline,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  const Text(
                    '标签',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  // 新增标签按钮
                  GestureDetector(
                    onTap: () async {
                      final newTag = await showTagCreateDialog(context);
                      if (newTag != null && mounted) {
                        setState(() {
                          if (!_selectedTags.contains(newTag.name)) {
                            _selectedTags.add(newTag.name);
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add,
                              size: 14, color: AppTheme.primaryColor),
                          SizedBox(width: 4),
                          Text(
                            '新建',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 标签列表
              _buildTagList(allTags),
            ],
          ),
        );
      },
    );
  }

  /// 构建标签列表（区分默认标签和自定义标签）
  Widget _buildTagList(List<Tag> tags) {
    final defaultTags = tags.where((t) => t.isDefault).toList();
    final customTags = tags.where((t) => !t.isDefault).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 默认标签部分
        if (defaultTags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '默认标签',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: defaultTags.map((tag) => _buildTagChip(tag)).toList(),
          ),
          if (customTags.isNotEmpty) const SizedBox(height: 16),
        ],
        // 自定义标签部分
        if (customTags.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '自定义标签',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: customTags.map((tag) => _buildTagChip(tag)).toList(),
          ),
        ],
        // 如果没有任何标签
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '暂无标签，点击"新建"添加',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 构建单个标签芯片
  Widget _buildTagChip(Tag tag) {
    final isSelected = _selectedTags.contains(tag.name);
    final color = _hexToColor(tag.color);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedTags.remove(tag.name);
          } else {
            _selectedTags.add(tag.name);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check : Icons.label_outline,
              size: 14,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              tag.name,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _hexToColor(String hex) => parseHexColor(hex);
}

/// 显示快速创建对话框（居中显示）
void showQuickAddModal(BuildContext context, {String? initialContent}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => QuickAddModal(initialContent: initialContent),
  );
}
