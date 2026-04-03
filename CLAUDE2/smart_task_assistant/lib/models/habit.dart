/// 习惯类型枚举
enum HabitType {
  water,      // 喝水
  stretch,    // 起身活动
  clockIn,    // 上班打卡
  clockOut,   // 下班打卡
}

/// 习惯模型
class Habit {
  final String id;
  String title;
  int targetCount;          // 目标数量（打卡类习惯为0）
  String unit;              // 单位
  String triggerType;       // 触发类型: interval/fixed
  int? intervalMinutes;     // 间隔分钟数
  String? fixedTime;        // 固定时间 HH:mm
  String scheduleType;      // 调度类型: weekdays
  int iconCode;             // 图标 Unicode 码点

  // 提醒方式设置
  bool soundEnabled;        // 启用声音
  bool vibrationEnabled;    // 启用振动
  bool voiceEnabled;        // 启用语音
  String? voiceText;        // 自定义语音内容
  String? voiceType;        // 语音类型：male/female/neutral/custom
  String? voiceStyle;       // 语音风格：standard/gentle/lively
  String voiceSpeed;        // 语速: slow/normal/fast
  String? customVoicePath;  // 自定义语音文件路径

  // 打卡习惯专属字段
  String? referenceTime;    // 参考时间 HH:mm
  int? advanceMinutes;      // 提前提醒分钟数

  // 其他
  bool isEnabled;           // 是否启用
  int sortOrder;            // 排序序号
  DateTime createdAt;
  DateTime updatedAt;

  Habit({
    required this.id,
    required this.title,
    this.targetCount = 1,
    this.unit = '次',
    required this.triggerType,
    this.intervalMinutes,
    this.fixedTime,
    this.scheduleType = 'weekdays',
    required this.iconCode,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.voiceEnabled = false,
    this.voiceText,
    this.voiceType = 'neutral',
    this.voiceStyle = 'standard',
    this.voiceSpeed = 'normal',
    this.customVoicePath,
    this.referenceTime,
    this.advanceMinutes,
    this.isEnabled = true,
    this.sortOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 获取习惯类型
  HabitType get habitType {
    if (id == 'habit_water') return HabitType.water;
    if (id == 'habit_stretch') return HabitType.stretch;
    if (id == 'habit_clock_in') return HabitType.clockIn;
    if (id == 'habit_clock_out') return HabitType.clockOut;
    return HabitType.water; // 默认
  }

  /// 是否需要记录（打卡类习惯不记录）
  bool get needsRecord {
    return habitType != HabitType.clockIn && habitType != HabitType.clockOut;
  }

  /// 是否有目标
  bool get hasTarget => targetCount > 0;

  /// 从 JSON 创建
  factory Habit.fromJson(Map<String, dynamic> json) {
    // 验证必需字段
    final id = json['id'];
    final title = json['title'];
    final createdAtStr = json['created_at'];
    final updatedAtStr = json['updated_at'];

    if (id == null || title == null || createdAtStr == null || updatedAtStr == null) {
      throw FormatException(
        'Invalid habit JSON: missing required fields. '
        'Required: id, title, created_at, updated_at. '
        'Got: ${json.keys.join(", ")}'
      );
    }

    try {
      return Habit(
        id: id as String,
        title: title as String,
        targetCount: json['target_count'] as int? ?? 1,
        unit: json['unit'] as String? ?? '次',
        triggerType: json['trigger_type'] as String? ?? 'interval',
        intervalMinutes: json['interval_minutes'] as int?,
        fixedTime: json['fixed_time'] as String?,
        scheduleType: json['schedule_type'] as String? ?? 'weekdays',
        iconCode: json['icon_code'] as int,
        soundEnabled: json['sound_enabled'] == 1 || json['sound_enabled'] == true,
        vibrationEnabled: json['vibration_enabled'] == 1 || json['vibration_enabled'] == true,
        voiceEnabled: json['voice_enabled'] == 1 || json['voice_enabled'] == true,
        voiceText: json['voice_text'] as String?,
        voiceType: json['voice_type'] as String?,
        voiceStyle: json['voice_style'] as String?,
        voiceSpeed: json['voice_speed'] as String? ?? 'normal',
        customVoicePath: json['custom_voice_path'] as String?,
        referenceTime: json['reference_time'] as String?,
        advanceMinutes: json['advance_minutes'] as int?,
        isEnabled: json['is_enabled'] == 1 || json['is_enabled'] == true,
        sortOrder: json['sort_order'] as int? ?? 0,
        createdAt: DateTime.parse(createdAtStr as String),
        updatedAt: DateTime.parse(updatedAtStr as String),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Failed to parse habit JSON: $e');
    }
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'target_count': targetCount,
      'unit': unit,
      'trigger_type': triggerType,
      'interval_minutes': intervalMinutes,
      'fixed_time': fixedTime,
      'schedule_type': scheduleType,
      'icon_code': iconCode,
      'sound_enabled': soundEnabled ? 1 : 0,
      'vibration_enabled': vibrationEnabled ? 1 : 0,
      'voice_enabled': voiceEnabled ? 1 : 0,
      'voice_text': voiceText,
      'voice_type': voiceType,
      'voice_style': voiceStyle,
      'voice_speed': voiceSpeed,
      'custom_voice_path': customVoicePath,
      'reference_time': referenceTime,
      'advance_minutes': advanceMinutes,
      'is_enabled': isEnabled ? 1 : 0,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// 复制并修改
  Habit copyWith({
    String? id,
    String? title,
    int? targetCount,
    String? unit,
    String? triggerType,
    int? intervalMinutes,
    String? fixedTime,
    String? scheduleType,
    int? iconCode,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? voiceEnabled,
    String? voiceText,
    String? voiceType,
    String? voiceStyle,
    String? voiceSpeed,
    String? customVoicePath,
    String? referenceTime,
    int? advanceMinutes,
    bool? isEnabled,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Habit(
      id: id ?? this.id,
      title: title ?? this.title,
      targetCount: targetCount ?? this.targetCount,
      unit: unit ?? this.unit,
      triggerType: triggerType ?? this.triggerType,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      fixedTime: fixedTime ?? this.fixedTime,
      scheduleType: scheduleType ?? this.scheduleType,
      iconCode: iconCode ?? this.iconCode,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceText: voiceText ?? this.voiceText,
      voiceType: voiceType ?? this.voiceType,
      voiceStyle: voiceStyle ?? this.voiceStyle,
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      customVoicePath: customVoicePath ?? this.customVoicePath,
      referenceTime: referenceTime ?? this.referenceTime,
      advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// 预设习惯
class PresetHabits {
  /// 获取默认习惯列表
  static List<Habit> get defaultHabits {
    return [
      // 喝水 - 需要记录
      Habit(
        id: 'habit_water',
        title: '喝水',
        targetCount: 8,
        unit: '杯',
        triggerType: 'interval',
        intervalMinutes: 60,
        scheduleType: 'weekdays',
        iconCode: 0x1F4A7, // 💧
        soundEnabled: true,
        vibrationEnabled: true,
        voiceEnabled: true,
        voiceText: '该休息一下了，喝水',
        voiceType: 'female',
        voiceStyle: 'lively',
        voiceSpeed: 'normal',
        isEnabled: true,
        sortOrder: 0,
      ),
      // 起身活动 - 需要记录
      Habit(
        id: 'habit_stretch',
        title: '起身活动',
        targetCount: 5,
        unit: '次',
        triggerType: 'interval',
        intervalMinutes: 90,
        scheduleType: 'weekdays',
        iconCode: 0x1F6B6, // 🚶
        soundEnabled: true,
        vibrationEnabled: true,
        voiceEnabled: true,
        voiceText: '时间到了，起身活动一下',
        voiceType: 'female',
        voiceStyle: 'lively',
        voiceSpeed: 'normal',
        isEnabled: true,
        sortOrder: 1,
      ),
      // 上班打卡 - 不需要记录
      Habit(
        id: 'habit_clock_in',
        title: '上班打卡',
        targetCount: 0, // 不设目标
        unit: '次',
        triggerType: 'fixed',
        fixedTime: '08:50', // 提醒时间
        referenceTime: '09:00', // 参考上班时间
        advanceMinutes: 10, // 提前10分钟
        scheduleType: 'weekdays',
        iconCode: 0x1F4E5, // 📥
        soundEnabled: true,
        vibrationEnabled: true,
        voiceEnabled: true,
        voiceText: '该打卡了',
        voiceType: 'female',
        voiceStyle: 'lively',
        voiceSpeed: 'normal',
        isEnabled: true,
        sortOrder: 2,
      ),
      // 下班打卡 - 不需要记录
      Habit(
        id: 'habit_clock_out',
        title: '下班打卡',
        targetCount: 0, // 不设目标
        unit: '次',
        triggerType: 'fixed',
        fixedTime: '18:00', // 提醒时间
        referenceTime: '18:00', // 参考下班时间
        advanceMinutes: 0, // 到点提醒
        scheduleType: 'weekdays',
        iconCode: 0x1F4E4, // 📤
        soundEnabled: true,
        vibrationEnabled: true,
        voiceEnabled: true,
        voiceText: '下班时间到了',
        voiceType: 'female',
        voiceStyle: 'lively',
        voiceSpeed: 'normal',
        isEnabled: true,
        sortOrder: 3,
      ),
    ];
  }

  /// 获取默认习惯的语音内容（根据语言）
  static Map<String, String> getVoiceTexts(bool isZh) {
    if (isZh) {
      return {
        'habit_water': '该休息一下了，喝水',
        'habit_stretch': '时间到了，起身活动一下',
        'habit_clock_in': '该打卡了',
        'habit_clock_out': '下班时间到了',
      };
    } else {
      return {
        'habit_water': 'Time for a break, drink water',
        'habit_stretch': 'Time to stretch',
        'habit_clock_in': 'Time to clock in',
        'habit_clock_out': 'Time to clock out',
      };
    }
  }
}