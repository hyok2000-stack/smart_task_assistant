/// 标签模型
class Tag {
  final String id;
  String name;
  String color;  // 十六进制颜色值
  String? icon;  // 图标名称
  int sortOrder;
  bool isDefault;  // 是否为默认标签
  DateTime createdAt;

  Tag({
    required this.id,
    required this.name,
    this.color = '#6366f1',
    this.icon,
    this.sortOrder = 0,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从 JSON 创建
  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#6366f1',
      icon: json['icon'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
      isDefault: (json['is_default'] as int?) == 1,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'sort_order': sortOrder,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改
  Tag copyWith({
    String? id,
    String? name,
    String? color,
    String? icon,
    int? sortOrder,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 默认标签列表
  static List<Tag> getDefaultTags() {
    return [
      Tag(
        id: 'default_work',
        name: '工作',
        color: '#3B82F6',
        sortOrder: 0,
        isDefault: true,
      ),
      Tag(
        id: 'default_personal',
        name: '个人',
        color: '#10B981',
        sortOrder: 1,
        isDefault: true,
      ),
      Tag(
        id: 'default_urgent',
        name: '紧急',
        color: '#EF4444',
        sortOrder: 2,
        isDefault: true,
      ),
      Tag(
        id: 'default_study',
        name: '学习',
        color: '#8B5CF6',
        sortOrder: 3,
        isDefault: true,
      ),
    ];
  }
}