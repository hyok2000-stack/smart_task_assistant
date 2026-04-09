import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../providers/task_provider.dart';
import '../services/ai_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_localizations.dart';

/// 添加/编辑任务页面
class AddTaskScreen extends StatefulWidget {
  final Task? task; // 用于编辑现有任务

  const AddTaskScreen({super.key, this.task});

  bool get isEditing => task != null;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  DateTime? _dueTime;
  TaskPriority _priority = TaskPriority.medium;
  TaskStatus _status = TaskStatus.pending; // 任务状态
  List<String> _selectedTagIds = [];
  int? _reminderMinutes; // 单选提醒时间
  bool _isRecurring = false; // 是否周期任务
  String _recurringRule = 'daily'; // 周期规则：daily, weekly, monthly
  bool _isProcessing = false;
  bool _aiDetected = false;
  String? _aiSuggestion;

  // 语音提醒设置
  bool _reminderVoiceEnabled = true; // 默认启用语音
  String? _reminderVoiceType; // male/female/neutral/custom
  String? _reminderVoiceStyle; // standard/gentle/lively
  String? _reminderVoiceSpeed; // slow/normal/fast
  String? _reminderCustomVoicePath; // 自定义语音文件路径

  // 预设提醒选项（简化版）- 在build方法中初始化
  late List<Map<String, dynamic>> _reminderOptions;

  // 自定义提醒时间
  int? _customReminderMinutes;
  bool _showCustomReminder = false;
  final _customReminderController = TextEditingController();

  // 语音测试播放状态流
  final _voicePlayingStream = StreamController<bool>.broadcast();

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，初始化现有任务数据
    if (widget.isEditing) {
      _titleController.text = widget.task!.title;
      _contentController.text = widget.task!.content ?? '';
      _dueTime = widget.task!.dueTime;
      _priority = widget.task!.priority;
      _status = widget.task!.status;
      _selectedTagIds = List.from(widget.task!.tagIds);
      _reminderMinutes = widget.task!.reminderMinutes;
      _isRecurring = widget.task!.isRecurring;
      _recurringRule = widget.task!.recurringRule ?? 'daily';

      // 初始化自定义提醒时间 - 将检查逻辑移到第一次 build 之后
      if (_reminderMinutes != null) {
        _customReminderMinutes = _reminderMinutes;
        _customReminderController.text = _reminderMinutes.toString();
      }

      // 初始化语音提醒设置
      _reminderVoiceEnabled = widget.task!.reminderVoiceEnabled;
      // 如果任务有自定义语音，使用它；否则使用默认值（女声、生动、正常）
      _reminderVoiceType = widget.task!.reminderVoiceType ?? 'female';
      _reminderVoiceStyle = widget.task!.reminderVoiceStyle ?? 'lively';
      _reminderVoiceSpeed = widget.task!.reminderVoiceSpeed ?? 'normal';
      _reminderCustomVoicePath = widget.task!.reminderCustomVoicePath;
    } else {
      // 新建任务时，默认启用提醒(15分钟)和语音（女声、生动、正常）
      _reminderMinutes = 10;
      _reminderVoiceType = 'female';
      _reminderVoiceStyle = 'lively';
      _reminderVoiceSpeed = 'normal';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _voicePlayingStream.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // 初始化提醒选项
    _reminderOptions = [
      {'minutes': null, 'label': l.noReminder},
      {'minutes': 10, 'label': '10${l.minBefore}'},
      {'minutes': 30, 'label': '30${l.minBefore}'},
      {'minutes': 60, 'label': l.hourBefore},
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? l.editTask : l.newTask),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _saveTask,
            child: Text(l.save),
          ),
        ],
      ),
      body: GradientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI智能识别提示
              if (_aiDetected && _aiSuggestion != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withOpacity(0.1),
                        AppTheme.secondaryColor.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.aiDetected,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _aiSuggestion!,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // 任务标题
              Text(
                l.taskTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                onChanged: _onTitleChanged,
                decoration: InputDecoration(
                  hintText: l.enterTaskTitle,
                  filled: true,
                  fillColor: Colors.white,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 20),
              // 任务详情
              Text(
                l.taskDetails,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                decoration: InputDecoration(
                  hintText: l.enterTaskDetails,
                  filled: true,
                  fillColor: Colors.white,
                ),
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 20),
              // 截止时间
              Text(
                l.deadline,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDueTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: _dueTime != null
                        ? LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withOpacity(0.08),
                              AppTheme.secondaryColor.withOpacity(0.08),
                            ],
                          )
                        : null,
                    color:
                        _dueTime == null ? Theme.of(context).cardColor : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _dueTime != null
                          ? AppTheme.primaryColor.withOpacity(0.3)
                          : Colors.grey.shade200,
                      width: _dueTime != null ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _dueTime != null
                              ? AppTheme.primaryColor.withOpacity(0.15)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_today_rounded,
                          size: 20,
                          color: _dueTime != null
                              ? AppTheme.primaryColor
                              : AppTheme.textHintColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dueTime != null
                              ? '${_dueTime!.month}/${_dueTime!.day} ${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}'
                              : l.selectDeadline,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: _dueTime != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: _dueTime != null
                                ? AppTheme.primaryColor
                                : AppTheme.textHintColor,
                          ),
                        ),
                      ),
                      if (_dueTime != null)
                        GestureDetector(
                          onTap: () => setState(() => _dueTime = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red.withOpacity(0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 提醒设置 - 两行布局
              if (_dueTime != null) ...[
                Text(
                  l.reminder,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行：不提醒、1小时前、10分钟前
                      Row(
                        children: [
                          _buildReminderChip(null, l.noReminder),
                          const SizedBox(width: 8),
                          _buildReminderChip(60, l.hourBefore),
                          const SizedBox(width: 8),
                          _buildReminderChip(10, '10${l.minBefore}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 第二行：30分钟前、自定义
                      Row(
                        children: [
                          _buildReminderChip(30, '30${l.minBefore}'),
                          const SizedBox(width: 8),
                          _buildReminderChip(-1, l.custom, isCustom: true),
                        ],
                      ),
                      // 自定义输入区域
                      if (_showCustomReminder) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customReminderController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: l.enterMinutes,
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textHintColor,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    suffixText: l.minBefore,
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                  onChanged: (value) {
                                    final minutes = int.tryParse(value);
                                    if (minutes != null && minutes > 0) {
                                      setState(() {
                                        _customReminderMinutes = minutes;
                                        _reminderMinutes = minutes;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              // 语音提醒设置
              if (_dueTime != null && _reminderMinutes != null) ...[
                Text(
                  l.isZh ? '语音提醒' : 'Voice Reminder',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 启用开关
                      SwitchListTile(
                        title: Text(l.isZh ? '启用语音提醒' : 'Enable Voice Reminder'),
                        subtitle: Text(
                          l.isZh ? '提醒时播放语音播报' : 'Play voice when reminding',
                          style: TextStyle(
                            color: _reminderVoiceEnabled
                                ? AppTheme.primaryColor
                                : AppTheme.textHintColor,
                            fontSize: 12,
                          ),
                        ),
                        value: _reminderVoiceEnabled,
                        onChanged: (value) {
                          setState(() => _reminderVoiceEnabled = value);
                        },
                        activeColor: AppTheme.primaryColor,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_reminderVoiceEnabled) ...[
                        const Divider(height: 24),
                        // 自定义语音文件选择
                        Row(
                          children: [
                            Text(l.isZh ? '自定义语音文件' : 'Custom Voice'),
                            const Spacer(),
                            Switch(
                              // 只有 voiceType 为 custom 且路径非空时才显示为开启
                              value: _reminderVoiceType == 'custom' && _reminderCustomVoicePath != null && _reminderCustomVoicePath!.isNotEmpty,
                              onChanged: (value) {
                                setState(() {
                                  if (value) {
                                    // 启用自定义语音（仅在已选择文件时才真正切换类型）
                                    if (_reminderCustomVoicePath != null && _reminderCustomVoicePath!.isNotEmpty) {
                                      _reminderVoiceType = 'custom';
                                    } else {
                                      // 没有文件时，先不切换类型，让用户去选择文件
                                      // 设置一个标记，选择文件后自动切换
                                      _reminderVoiceType = 'custom';
                                    }
                                  } else {
                                    // 禁用自定义语音，使用默认设置（女声、生动、正常）
                                    _reminderVoiceType = 'female';
                                    _reminderCustomVoicePath = null;
                                  }
                                });
                              },
                              activeColor: AppTheme.primaryColor,
                            ),
                          ],
                        ),
                        // 当启用自定义语音时显示文件选择
                        if (_reminderVoiceType == 'custom') ...[
                          const SizedBox(height: 16),
                          if (_reminderCustomVoicePath != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: Text(
                                      _reminderCustomVoicePath!.split('/').last,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: _pickCustomVoice,
                                  icon: const Icon(Icons.folder_open, size: 18),
                                  label: Text(l.isZh ? '更换' : 'Change'),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _reminderCustomVoicePath = null;
                                    });
                                  },
                                ),
                              ],
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _pickCustomVoice,
                                icon: const Icon(Icons.audio_file, size: 20),
                                label: Text(l.isZh ? '选择语音文件' : 'Select Voice File'),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            _reminderCustomVoicePath != null
                                ? (l.isZh ? '已启用自定义语音，将使用您选择的音频文件' : 'Custom voice enabled, will use your selected audio file')
                                : (l.isZh ? '请选择一个音频文件作为提醒语音' : 'Please select an audio file for reminder voice'),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                      const Divider(height: 24),
                      // 语音测试按钮
                      Row(
                        children: [
                          const Spacer(),
                          StreamBuilder<bool>(
                            stream: _voicePlayingStream.stream,
                            initialData: false,
                            builder: (context, snapshot) {
                              final isPlaying = snapshot.data ?? false;
                              return OutlinedButton.icon(
                                onPressed: _testVoice,
                                icon: Icon(
                                  isPlaying ? Icons.stop : Icons.volume_up,
                                  size: 18,
                                  color: isPlaying ? Colors.red : null,
                                ),
                                label: Text(
                                  isPlaying
                                      ? (l.isZh ? '停止播放' : 'Stop')
                                      : (l.isZh ? '测试语音' : 'Test Voice'),
                                  style: TextStyle(
                                    color: isPlaying ? Colors.red : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              // 优先级
              Text(
                l.priority,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildPriorityChip(
                    TaskPriority.low,
                    l.priorityLowShort,
                    AppTheme.lowPriorityColor,
                  ),
                  const SizedBox(width: 12),
                  _buildPriorityChip(
                    TaskPriority.medium,
                    l.priorityMediumShort,
                    AppTheme.mediumPriorityColor,
                  ),
                  const SizedBox(width: 12),
                  _buildPriorityChip(
                    TaskPriority.high,
                    l.priorityHighShort,
                    AppTheme.highPriorityColor,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 标签选择
              Text(
                l.tagsLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Consumer<TaskProvider>(
                builder: (context, provider, child) {
                  // 默认标签
                  final defaultTags = [
                    Tag(
                      id: 'default_work',
                      name: l.tagWork,
                      color: '#3B82F6',
                      isDefault: true,
                    ),
                    Tag(
                      id: 'default_personal',
                      name: l.tagPersonal,
                      color: '#10B981',
                      isDefault: true,
                    ),
                    Tag(
                      id: 'default_urgent',
                      name: l.tagUrgent,
                      color: '#EF4444',
                      isDefault: true,
                    ),
                    Tag(
                      id: 'default_study',
                      name: l.tagStudy,
                      color: '#8B5CF6',
                      isDefault: true,
                    ),
                  ];

                  // 合并默认标签和自定义标签（去重）
                  final allTags = [...defaultTags];
                  for (final tag in provider.tags) {
                    if (!defaultTags.any((t) => t.id == tag.id)) {
                      allTags.add(tag);
                    }
                  }

                  if (allTags.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.label_outline,
                            color: AppTheme.textHintColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.isZh
                                ? '暂无标签，请在设置中添加'
                                : 'No tags, please add in settings',
                            style: TextStyle(
                              color: AppTheme.textHintColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // 区分默认标签和自定义标签
                  final tagsWithDefault = allTags.map((tag) {
                    return {
                      'tag': tag,
                      'isDefault': defaultTags.any((t) => t.id == tag.id),
                    };
                  }).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 默认标签组
                      if (defaultTags.any(
                        (t) =>
                            _selectedTagIds.contains(t.id) ||
                            !provider.tags.any((pt) => pt.id == t.id),
                      )) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 4,
                                ),
                                child: Text(
                                  l.defaultTags,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textHintColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: defaultTags.map((tag) {
                                  final isSelected = _selectedTagIds.contains(
                                    tag.id,
                                  );
                                  return _buildTagChip(tag, isSelected);
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // 自定义标签组
                      if (provider.tags.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 4,
                            right: 4,
                            bottom: 4,
                          ),
                          child: Text(
                            l.customTags,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textHintColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: provider.tags.map((tag) {
                            final isSelected = _selectedTagIds.contains(tag.id);
                            return _buildTagChip(tag, isSelected);
                          }).toList(),
                        ),
                      ],
                    ],
                  );
                },
              ),
              // 周期任务设置
              const SizedBox(height: 20),
              Text(
                l.recurringTaskSettings,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text(l.setAsRecurring),
                      subtitle: Text(
                        _isRecurring ? l.autoCreateNext : l.off,
                        style: TextStyle(
                          color: _isRecurring
                              ? AppTheme.primaryColor
                              : AppTheme.textHintColor,
                          fontSize: 12,
                        ),
                      ),
                      value: _isRecurring,
                      onChanged: (value) {
                        setState(() => _isRecurring = value);
                      },
                      activeColor: AppTheme.primaryColor,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_isRecurring) ...[
                      const Divider(height: 24),
                      Text(l.repeatCycle, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildRecurringChip('daily', l.daily),
                          const SizedBox(width: 8),
                          _buildRecurringChip('weekly', l.weekly),
                          const SizedBox(width: 8),
                          _buildRecurringChip('monthly', l.monthly),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 任务状态（仅编辑模式显示）
              if (widget.isEditing) ...[
                const SizedBox(height: 20),
                Text(
                  l.taskStatus,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                _buildStatusSelector(l),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityChip(TaskPriority priority, String label, Color color) {
    final isSelected = _priority == priority;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _priority = priority),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppTheme.textSecondaryColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建状态选择器
  Widget _buildStatusSelector(AppLocalizations l) {
    return Row(
      children: [
        _buildStatusChip(
          TaskStatus.pending,
          l.statusPending,
          AppTheme.warningColor,
          Icons.schedule_rounded,
        ),
        const SizedBox(width: 8),
        _buildStatusChip(
          TaskStatus.inProgress,
          l.statusInProgress,
          AppTheme.infoColor,
          Icons.play_arrow_rounded,
        ),
        const SizedBox(width: 8),
        _buildStatusChip(
          TaskStatus.completed,
          l.completed,
          AppTheme.successColor,
          Icons.check_circle_rounded,
        ),
      ],
    );
  }

  Widget _buildStatusChip(
    TaskStatus status,
    String label,
    Color color,
    IconData icon,
  ) {
    final isSelected = _status == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _status = status),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade50,
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
                  color: isSelected ? color : AppTheme.textHintColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecurringChip(String rule, String label) {
    final isSelected = _recurringRule == rule;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _recurringRule = rule),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color:
                    isSelected ? AppTheme.primaryColor : AppTheme.textHintColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建提醒选项芯片
  Widget _buildReminderChip(
    int? minutes,
    String label, {
    bool isCustom = false,
  }) {
    bool isSelected;
    if (isCustom) {
      isSelected = _showCustomReminder ||
          (_customReminderMinutes != null &&
              !_reminderOptions.any(
                (opt) => opt['minutes'] == _reminderMinutes,
              ));
    } else if (minutes == null) {
      // "不提醒"选项
      isSelected = _reminderMinutes == null &&
          !_showCustomReminder &&
          _customReminderMinutes == null;
    } else {
      isSelected = _reminderMinutes == minutes && !_showCustomReminder;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isCustom) {
              _showCustomReminder = true;
              // 如果已有自定义时间，保持它
              if (_customReminderMinutes != null) {
                _reminderMinutes = _customReminderMinutes;
              }
            } else {
              _showCustomReminder = false;
              _reminderMinutes = minutes;
              _customReminderMinutes = null;
              _customReminderController.clear();
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.15)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    isSelected ? AppTheme.primaryColor : AppTheme.textHintColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTitleChanged(String value) {
    // 简单的AI识别模拟
    if (value.contains('明天') || value.contains('后天')) {
      setState(() {
        _aiDetected = true;
        _aiSuggestion = '检测到时间关键词，建议设置截止时间';
      });
    } else if (value.contains('紧急') || value.contains('重要')) {
      setState(() {
        _aiDetected = true;
        _aiSuggestion = '检测到优先级关键词，建议设为高优先级';
        _priority = TaskPriority.high;
      });
    } else {
      setState(() {
        _aiDetected = false;
        _aiSuggestion = null;
      });
    }
  }

  /// 选择自定义语音文件
  Future<void> _pickCustomVoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final sourcePath = result.files.single.path!;

        // 将文件复制到应用内部存储，确保后台服务也能访问
        final internalPath = await _copyVoiceToInternalStorage(sourcePath);

        setState(() {
          _reminderCustomVoicePath = internalPath ?? sourcePath;
        });
      }
    } catch (e) {
      debugPrint('选择语音文件失败: $e');
    }
  }

  /// 将语音文件复制到应用内部存储
  Future<String?> _copyVoiceToInternalStorage(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return null;

      // 创建 voices 目录
      final voicesDir = Directory('${(await getApplicationDocumentsDirectory())}/voices');
      if (!await voicesDir.exists()) {
        await voicesDir.create(recursive: true);
      }

      // 生成唯一文件名
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}${sourcePath.substring(sourcePath.lastIndexOf('.'))}';
      final destFile = File('${voicesDir.path}/$fileName');

      // 如果目标文件已存在，先删除
      if (await destFile.exists()) {
        await destFile.delete();
      }

      // 复制文件
      await sourceFile.copy(destFile.path);
      debugPrint('语音文件已复制到内部存储: ${destFile.path}');
      return destFile.path;
    } catch (e) {
      debugPrint('复制语音文件到内部存储失败: $e');
      return null;
    }
  }

  /// 测试语音播放（再次点击停止）
  Future<void> _testVoice() async {
    final ttsService = TTSService();
    // 无论当前是否在播放，先停止所有语音
    await ttsService.stopSpeaking();
    _voicePlayingStream.add(false);

    _voicePlayingStream.add(true);
    // 构造与实际任务提醒一致的语音文本（优先级前缀 + 时间上下文 + 标题）
    final priorityPrefix = _getPriorityPrefix(_priority);
    final timeContext = _getTimeContext();
    final taskTitle = _titleController.text.trim();
    final testText = '$priorityPrefix$timeContext${taskTitle.isNotEmpty ? taskTitle : '示例任务'}';
    await ttsService.testVoice(
      text: testText,
      voiceType: _reminderVoiceType,
      voiceStyle: _reminderVoiceStyle,
      speed: _reminderVoiceSpeed,
      customVoicePath: _reminderCustomVoicePath,
    );
    _voicePlayingStream.add(false);
  }

  /// 获取优先级前缀（与 TTSService 一致）
  String _getPriorityPrefix(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return '紧急任务提醒';
      case TaskPriority.medium:
        return '任务提醒';
      case TaskPriority.low:
        return '温和提醒';
    }
  }

  /// 获取时间上下文（与 TTSService 一致）
  String _getTimeContext() {
    if (_reminderMinutes == null || _dueTime == null) return '';
    final now = DateTime.now();
    final diff = _dueTime!.difference(now);
    if (diff.inMinutes <= 0) {
      return '任务到期了，';
    } else if (diff.inHours == 0) {
      return '${diff.inMinutes}分钟后需要完成，';
    } else if (diff.inHours == 1) {
      return '1小时后需要完成，';
    } else {
      return '${diff.inHours}小时后需要完成，';
    }
  }

  Future<void> _selectDueTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueTime ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dueTime ?? DateTime.now()),
      );

      if (time != null) {
        setState(() {
          _dueTime = DateTime(
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

  Future<void> _saveTask() async {
    final l = context.l;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.pleaseEnterTitle)));
      return;
    }

    setState(() => _isProcessing = true);

    final provider = context.read<TaskProvider>();

    // 调试日志：输出选中的标签ID
    print('===== 保存任务 =====');
    print('任务标题: ${_titleController.text.trim()}');
    print('选中的标签ID: $_selectedTagIds');
    print('标签数量: ${_selectedTagIds.length}');

    // 防御性检查：确保 voiceType 和 customVoicePath 一致
    // 如果 voiceType 为 'custom' 但路径为空，则回退到默认语音类型
    if (_reminderVoiceType == 'custom' &&
        (_reminderCustomVoicePath == null || _reminderCustomVoicePath!.isEmpty)) {
      debugPrint('⚠️ 语音类型为自定义但路径为空，保存时回退到女声');
      _reminderVoiceType = 'female';
      _reminderCustomVoicePath = null;
    }

    if (widget.isEditing) {
      // 编辑模式：更新现有任务
      // 处理状态变化时的完成时间
      DateTime? completedAt = widget.task!.completedAt;
      if (_status == TaskStatus.completed &&
          widget.task!.status != TaskStatus.completed) {
        completedAt = DateTime.now();
      } else if (_status != TaskStatus.completed &&
          widget.task!.status == TaskStatus.completed) {
        completedAt = null;
      }

      final updatedTask = widget.task!.copyWith(
        title: _titleController.text.trim(),
        content: _contentController.text.trim().isNotEmpty
            ? _contentController.text.trim()
            : null,
        dueTime: _dueTime,
        priority: _priority,
        status: _status,
        completedAt: completedAt,
        tagIds: _selectedTagIds,
        reminderMinutes: _reminderMinutes,
        reminderVoiceEnabled: _reminderVoiceEnabled,
        reminderVoiceType: _reminderVoiceType,
        reminderVoiceStyle: _reminderVoiceStyle,
        reminderVoiceSpeed: _reminderVoiceSpeed,
        reminderCustomVoicePath: _reminderCustomVoicePath,
        isRecurring: _isRecurring,
        recurringRule: _recurringRule,
      );

      await provider.updateTask(updatedTask);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.taskUpdated)));
      }
    } else {
      // 新建模式：创建新任务
      final task = Task(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        content: _contentController.text.trim().isNotEmpty
            ? _contentController.text.trim()
            : null,
        dueTime: _dueTime,
        priority: _priority,
        tagIds: _selectedTagIds,
        reminderMinutes: _reminderMinutes,
        reminderVoiceEnabled: _reminderVoiceEnabled,
        reminderVoiceType: _reminderVoiceType,
        reminderVoiceStyle: _reminderVoiceStyle,
        reminderVoiceSpeed: _reminderVoiceSpeed,
        reminderCustomVoicePath: _reminderCustomVoicePath,
        isRecurring: _isRecurring,
        recurringRule: _isRecurring ? _recurringRule : null,
      );

      await provider.addTask(task);

      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Color _parseColor(String hexColor) {
    try {
      hexColor = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    } catch (e) {
      return AppTheme.primaryColor;
    }
  }

  /// 构建标签选择芯片
  Widget _buildTagChip(Tag tag, bool isSelected) {
    final color = _parseColor(tag.color);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilterChip(
      label: Text(
        tag.name,
        style: TextStyle(
          color: isSelected ? color : (isDark ? Colors.white : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedTagIds.add(tag.id);
          } else {
            _selectedTagIds.remove(tag.id);
          }
        });
      },
      selectedColor: color.withOpacity(0.2),
      checkmarkColor: Colors.white, // 改为白色打勾号
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
