import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../services/tts_service.dart';
import '../services/habit_service.dart';
import '../utils/app_localizations.dart';

/// 习惯设置对话框
class HabitSettingsDialog extends StatefulWidget {
  final Habit habit;

  const HabitSettingsDialog({
    super.key,
    required this.habit,
  });

  @override
  State<HabitSettingsDialog> createState() => _HabitSettingsDialogState();
}

class _HabitSettingsDialogState extends State<HabitSettingsDialog> {
  late Habit _editedHabit;
  final _voicePlayingStream = StreamController<bool>.broadcast();

  @override
  void initState() {
    super.initState();
    _editedHabit = widget.habit;
  }

  @override
  void dispose() {
    _voicePlayingStream.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isClockHabit = _editedHabit.id == 'habit_clock_in' ||
        _editedHabit.id == 'habit_clock_out';

    return AlertDialog(
      title: Text('${_editedHabit.title}设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 目标设置（非打卡习惯）
            if (!isClockHabit) ...[
              _buildTargetSection(),
              const Divider(),
            ],
            // 时间设置
            _buildTimeSection(),
            const Divider(),
            // 提醒方式设置
            _buildReminderSection(),
            const Divider(),
            // 语音设置
            _buildVoiceSection(),
            const SizedBox(height: 16),
            // 启用开关
            _buildEnabledSwitch(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saveSettings,
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// 构建目标设置部分
  Widget _buildTargetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目标设置',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('目标数量: '),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: TextField(
                controller: TextEditingController(
                  text: _editedHabit.targetCount.toString(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                onChanged: (value) {
                  _editedHabit = _editedHabit.copyWith(
                    targetCount: int.tryParse(value) ?? 1,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(_editedHabit.unit),
          ],
        ),
      ],
    );
  }

  /// 构建时间设置部分
  Widget _buildTimeSection() {
    final isClockHabit = _editedHabit.id == 'habit_clock_in' ||
        _editedHabit.id == 'habit_clock_out';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时间设置',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        // 间隔时间（非打卡习惯）
        if (_editedHabit.triggerType == 'interval' && !isClockHabit) ...[
          Row(
            children: [
              const Text('间隔时间: '),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: TextEditingController(
                    text: _editedHabit.intervalMinutes.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onChanged: (value) {
                    _editedHabit = _editedHabit.copyWith(
                      intervalMinutes: int.tryParse(value) ?? 60,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Text('分钟'),
            ],
          ),
          const SizedBox(height: 12),
          // 提醒范围选择
          Row(
            children: [
              Text(context.l.habitScheduleType),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _editedHabit.scheduleType,
                items: const [
                  DropdownMenuItem(
                    value: 'weekdays',
                    child: Text('工作日'),
                  ),
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text('自然日'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _editedHabit = _editedHabit.copyWith(scheduleType: value);
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _editedHabit.scheduleType == 'weekdays'
                ? context.l.habitScheduleTypeWeekdaysHint
                : context.l.habitScheduleTypeDailyHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
        // 固定时间（打卡习惯）
        if (_editedHabit.triggerType == 'fixed' && !isClockHabit) ...[
          Row(
            children: [
              const Text('提醒时间: '),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _selectTime,
                child: Text(_editedHabit.fixedTime ?? '选择时间'),
              ),
            ],
          ),
        ],
        // 提醒范围选择（打卡习惯）
        if (isClockHabit) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(context.l.habitScheduleType),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _editedHabit.scheduleType,
                items: const [
                  DropdownMenuItem(
                    value: 'weekdays',
                    child: Text('工作日'),
                  ),
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text('自然日'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _editedHabit = _editedHabit.copyWith(scheduleType: value);
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _editedHabit.scheduleType == 'weekdays'
                ? context.l.habitScheduleTypeWeekdaysHint
                : context.l.habitScheduleTypeDailyHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
          // 参考时间（打卡习惯）- 可编辑
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${_editedHabit.id == 'habit_clock_in' ? '上班时间' : '下班时间'}: ',
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _selectReferenceTime,
                child: Text(_editedHabit.referenceTime ?? '设置时间'),
              ),
            ],
          ),
          // 提前提醒分钟数（上班打卡）
          if (_editedHabit.id == 'habit_clock_in') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('提前 '),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: TextEditingController(
                      text: (_editedHabit.advanceMinutes ?? 10).toString(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    onChanged: (value) {
                      _editedHabit = _editedHabit.copyWith(
                        advanceMinutes: int.tryParse(value) ?? 10,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('分钟提醒'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '提醒时间将根据上班时间提前${_editedHabit.advanceMinutes ?? 10}分钟计算',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.blue[700],
                  ),
            ),
          ],
        ],
      ],
    );
  }

  /// 构建提醒方式设置部分
  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '提醒方式',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('声音提醒'),
          subtitle: const Text('播放提示音'),
          value: _editedHabit.soundEnabled,
          onChanged: (value) {
            setState(() {
              _editedHabit = _editedHabit.copyWith(soundEnabled: value);
            });
          },
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('振动提醒'),
          subtitle: const Text('设备振动'),
          value: _editedHabit.vibrationEnabled,
          onChanged: (value) {
            setState(() {
              _editedHabit = _editedHabit.copyWith(vibrationEnabled: value);
            });
          },
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('语音提醒'),
          subtitle: const Text('使用 TTS 语音播报'),
          value: _editedHabit.voiceEnabled,
          onChanged: (value) {
            setState(() {
              _editedHabit = _editedHabit.copyWith(voiceEnabled: value);
            });
          },
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// 构建语音设置部分
  Widget _buildVoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '语音设置',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: TextEditingController(text: _editedHabit.voiceText),
          decoration: const InputDecoration(
            labelText: '语音内容',
            hintText: '输入自定义语音内容',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          onChanged: (value) {
            _editedHabit = _editedHabit.copyWith(voiceText: value);
          },
        ),
        const SizedBox(height: 12),
        // 自定义语音文件选择
        Row(
          children: [
            const Text('自定义语音文件'),
            const Spacer(),
            Switch(
              value: _editedHabit.voiceType == 'custom' && _editedHabit.customVoicePath != null && _editedHabit.customVoicePath!.isNotEmpty,
              onChanged: (value) async {
                if (value) {
                  // 先选择文件，选择成功后再启用自定义语音
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.audio,
                    allowMultiple: false,
                  );
                  if (result != null && result.files.single.path != null) {
                    setState(() {
                      _editedHabit = _editedHabit.copyWith(
                        voiceType: 'custom',
                        customVoicePath: result.files.single.path,
                      );
                    });
                  }
                } else {
                  setState(() {
                    _editedHabit = _editedHabit.copyWith(
                      voiceType: 'female',
                      voiceStyle: 'lively',
                      voiceSpeed: 'normal',
                      customVoicePath: null,
                    );
                  });
                }
              },
            ),
          ],
        ),
        // 当启用自定义语音时显示文件选择
        if (_editedHabit.voiceType == 'custom' && _editedHabit.customVoicePath != null) ...[
          const SizedBox(height: 12),
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
                    _editedHabit.customVoicePath!.split('/').last,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickCustomVoice,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('更换'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  setState(() => _editedHabit = _editedHabit.copyWith(
                    voiceType: 'female',
                    voiceStyle: 'lively',
                    voiceSpeed: 'normal',
                    customVoicePath: null,
                  ));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '已启用自定义语音，将使用您上传的音频文件',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 12),
        // 测试语音按钮
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
                    isPlaying ? '停止播放' : '测试语音',
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
    );
  }

  /// 构建启用开关
  Widget _buildEnabledSwitch() {
    return SwitchListTile(
      title: const Text('启用习惯'),
      subtitle: const Text('开启后将按设置触发提醒'),
      value: _editedHabit.isEnabled,
      onChanged: (value) {
        setState(() {
          _editedHabit = _editedHabit.copyWith(isEnabled: value);
        });
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  /// 选择提醒时间
  Future<void> _selectTime() async {
    final now = DateTime.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: now.hour,
        minute: now.minute,
      ),
    );

    if (picked != null) {
      setState(() {
        _editedHabit = _editedHabit.copyWith(
          fixedTime: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
        );
      });
    }
  }

  /// 选择参考时间（上班/下班时间）
  Future<void> _selectReferenceTime() async {
    TimeOfDay initialTime;
    if (_editedHabit.referenceTime != null && _editedHabit.referenceTime!.contains(':')) {
      final parts = _editedHabit.referenceTime!.split(':');
      initialTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    } else {
      initialTime = const TimeOfDay(hour: 9, minute: 0);
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      setState(() {
        _editedHabit = _editedHabit.copyWith(
          referenceTime: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
        );
      });
    }
  }

  /// 测试语音（再次点击停止播放）
  Future<void> _testVoice() async {
    final ttsService = TTSService();
    // 无论当前是否在播放，先停止所有语音
    await ttsService.stopSpeaking();
    _voicePlayingStream.add(false);

    _voicePlayingStream.add(true);
    // 使用 HabitService.getVoiceText() 获取实际提醒语音内容
    final voiceText = HabitService().getVoiceText(_editedHabit, true);
    await ttsService.testVoice(
      text: voiceText,
      voiceType: _editedHabit.voiceType,
      voiceStyle: _editedHabit.voiceStyle,
      speed: _editedHabit.voiceSpeed,
      customVoicePath: _editedHabit.customVoicePath,
    );
    _voicePlayingStream.add(false);
  }

  /// 选择自定义语音文件
  Future<void> _pickCustomVoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _editedHabit = _editedHabit.copyWith(
            customVoicePath: result.files.single.path,
          );
        });
      }
    } catch (e) {
      debugPrint('选择语音文件失败: $e');
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    final provider = context.read<HabitProvider>();

    // 对于打卡习惯，更新 fixedTime 为参考时间（用于计算）
    final isClockHabit = _editedHabit.id == 'habit_clock_in' || _editedHabit.id == 'habit_clock_out';
    if (isClockHabit && _editedHabit.referenceTime != null) {
      _editedHabit = _editedHabit.copyWith(fixedTime: _editedHabit.referenceTime);
    }

    await provider.updateHabit(_editedHabit);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}