import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';
import '../models/tag.dart';
import '../models/habit.dart';
import '../models/habit_log.dart';

/// 数据库帮助类
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  // 用于防止并发初始化的锁
  Future<Database>? _databaseInitLock;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  /// 获取数据库实例
  Future<Database> get database async {
    // 使用锁机制防止并发初始化
    _databaseInitLock ??= _initDatabaseInternal();
    return _databaseInitLock!;
  }

  /// 内部初始化方法
  Future<Database> _initDatabaseInternal() async {
    // 每次都检查数据库连接状态，确保应用重启后能正确连接
    if (_database != null) {
      // 检查数据库是否已关闭
      try {
        await _database!.query('sqlite_master', limit: 1);
        debugPrint('数据库连接正常');
        return _database!;
      } catch (e) {
        // 数据库已关闭，需要重新初始化
        debugPrint('⚠️ 数据库连接已关闭或无效，正在重新初始化: $e');
        _database = null;
        // 继续执行下面的初始化代码
      }
    }

    debugPrint('📦 正在初始化数据库...');
    try {
      _database = await _initDatabase();
      debugPrint('✅ 数据库初始化完成');
      return _database!;
    } catch (e) {
      debugPrint('❌ 数据库初始化失败: $e');
      // 重置锁以便下次重试
      _databaseInitLock = null;
      rethrow;
    }
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'smart_task_assistant.db');
    return await openDatabase(
      path,
      version: 9, // 更新版本号为 9（统一任务语音默认开关）
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    // 任务表
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT,
        status INTEGER DEFAULT 0,
        priority INTEGER DEFAULT 1,
        start_time TEXT,
        due_time TEXT,
        completed_at TEXT,
        assignee TEXT,
        parent_id TEXT,
        is_recurring INTEGER DEFAULT 0,
        recurring_rule TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        tag_ids TEXT,
        attachment_paths TEXT,
        reminder_minutes INTEGER,
        reminder_dismissed INTEGER DEFAULT 0,
        reminder_voice_enabled INTEGER DEFAULT 1,
        reminder_voice_type TEXT DEFAULT 'neutral',
        reminder_voice_style TEXT DEFAULT 'standard',
        reminder_voice_speed TEXT DEFAULT 'normal',
        reminder_custom_voice_path TEXT
      )
    ''');

    // 标签表
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#6366f1',
        icon TEXT,
        sort_order INTEGER DEFAULT 0,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 提醒表
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        remind_at TEXT NOT NULL,
        is_sent INTEGER DEFAULT 0,
        type TEXT DEFAULT 'normal',
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    // 任务分发表
    await db.execute('''
      CREATE TABLE task_distributions (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        assignee_name TEXT NOT NULL,
        assignee_email TEXT,
        assignee_phone TEXT,
        status INTEGER DEFAULT 0,
        distributed_at TEXT NOT NULL,
        accepted_at TEXT,
        completed_at TEXT,
        due_date TEXT,
        notes TEXT,
        progress REAL DEFAULT 0,
        response_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
      )
    ''');

    // 创建性能优化索引
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_due_time ON tasks(due_time)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_completed_at ON tasks(completed_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tasks_status_due_time ON tasks(status, due_time)');

    // 插入默认标签
    await _insertDefaultTags(db);

    // 创建习惯表
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        target_count INTEGER NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT '次',
        trigger_type TEXT NOT NULL DEFAULT 'interval',
        interval_minutes INTEGER,
        fixed_time TEXT,
        schedule_type TEXT NOT NULL DEFAULT 'weekdays',
        icon_code INTEGER NOT NULL,
        sound_enabled INTEGER NOT NULL DEFAULT 1,
        vibration_enabled INTEGER NOT NULL DEFAULT 1,
        voice_enabled INTEGER NOT NULL DEFAULT 1,
        voice_text TEXT,
        voice_type TEXT DEFAULT 'neutral',
        voice_style TEXT DEFAULT 'standard',
        voice_speed TEXT DEFAULT 'normal',
        custom_voice_path TEXT,
        reference_time TEXT,
        advance_minutes INTEGER,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 创建习惯日志表
    await db.execute('''
      CREATE TABLE habit_logs (
        id TEXT PRIMARY KEY,
        habit_id TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        status INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (habit_id) REFERENCES habits (id) ON DELETE CASCADE
      )
    ''');

    // 创建习惯相关索引
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_habits_is_enabled ON habits(is_enabled)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_habits_sort_order ON habits(sort_order)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_id ON habit_logs(habit_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_habit_logs_completed_at ON habit_logs(completed_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, completed_at)');

    // 插入默认习惯
    await _insertDefaultHabits(db);
  }

  /// 插入默认习惯
  Future<void> _insertDefaultHabits(Database db) async {
    final defaultHabits = PresetHabits.defaultHabits;

    for (var habit in defaultHabits) {
      try {
        await db.insert('habits', habit.toJson(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        debugPrint('默认习惯已插入: ${habit.title}');
      } catch (e) {
        debugPrint('插入默认习惯失败: ${habit.title}, 错误: $e');
      }
    }
  }

  /// 插入默认标签
  Future<void> _insertDefaultTags(Database db) async {
    final defaultTags = Tag.getDefaultTags();

    for (var tag in defaultTags) {
      await db.insert('tags', tag.toJson(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 版本1 -> 版本2: 添加提醒相关字段
    if (oldVersion < 2) {
      try {
        await db
            .execute('ALTER TABLE tasks ADD COLUMN reminder_minutes INTEGER');
      } catch (e) {
        // 列已存在，忽略错误
      }
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_dismissed INTEGER DEFAULT 0');
      } catch (e) {
        // 列已存在，忽略错误
      }
    }

    // 版本2 -> 版本3: 添加 is_default 字段到标签表
    if (oldVersion < 3) {
      try {
        await db.execute(
            'ALTER TABLE tags ADD COLUMN is_default INTEGER DEFAULT 0');
      } catch (e) {
        // 列已存在，忽略错误
      }

      // 更新现有默认标签的 is_default 字段
      final defaultTagIds = [
        'tag_work',
        'tag_personal',
        'tag_study',
        'tag_urgent',
        'default_work',
        'default_personal',
        'default_urgent',
        'default_study'
      ];
      for (var tagId in defaultTagIds) {
        await db.update(
          'tags',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [tagId],
        );
      }
    }

    // 版本3 -> 版本4: 添加任务分发表
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE task_distributions (
          id TEXT PRIMARY KEY,
          task_id TEXT NOT NULL,
          assignee_name TEXT NOT NULL,
          assignee_email TEXT,
          assignee_phone TEXT,
          status INTEGER DEFAULT 0,
          distributed_at TEXT NOT NULL,
          accepted_at TEXT,
          completed_at TEXT,
          due_date TEXT,
          notes TEXT,
          progress REAL DEFAULT 0,
          response_message TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
        )
      ''');
    }

    // 版本4 -> 版本5: 添加性能优化索引
    if (oldVersion < 5) {
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tasks_due_time ON tasks(due_time)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tasks_completed_at ON tasks(completed_at)');
        debugPrint('数据库索引创建成功');
      } catch (e) {
        debugPrint('创建数据库索引失败: $e');
      }
    }

    // 版本5 -> 版本6: 添加习惯管理相关表
    if (oldVersion < 6) {
      // 创建习惯表
      await db.execute('''
        CREATE TABLE habits (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          target_count INTEGER NOT NULL DEFAULT 1,
          unit TEXT NOT NULL DEFAULT '次',
          trigger_type TEXT NOT NULL DEFAULT 'interval',
          interval_minutes INTEGER,
          fixed_time TEXT,
          schedule_type TEXT NOT NULL DEFAULT 'weekdays',
          icon_code INTEGER NOT NULL,
          sound_enabled INTEGER NOT NULL DEFAULT 1,
          vibration_enabled INTEGER NOT NULL DEFAULT 1,
          voice_enabled INTEGER NOT NULL DEFAULT 1,
          voice_text TEXT,
          voice_speed TEXT DEFAULT 'normal',
          reference_time TEXT,
          advance_minutes INTEGER,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // 创建习惯日志表
      await db.execute('''
        CREATE TABLE habit_logs (
          id TEXT PRIMARY KEY,
          habit_id TEXT NOT NULL,
          count INTEGER NOT NULL DEFAULT 1,
          status INTEGER NOT NULL DEFAULT 0,
          completed_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (habit_id) REFERENCES habits (id) ON DELETE CASCADE
        )
      ''');

      // 创建习惯相关索引
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habits_is_enabled ON habits(is_enabled)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habits_sort_order ON habits(sort_order)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_id ON habit_logs(habit_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habit_logs_completed_at ON habit_logs(completed_at)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, completed_at)');

      debugPrint('习惯管理表创建成功');

      // 插入默认习惯
      await _insertDefaultHabits(db);
    }

    // 版本6 -> 版本7: 添加任务语音提醒字段
    if (oldVersion < 7) {
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_voice_enabled INTEGER DEFAULT 1');
      } catch (e) {
        debugPrint('列 reminder_voice_enabled 已存在: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_voice_type TEXT DEFAULT \'neutral\'');
      } catch (e) {
        debugPrint('列 reminder_voice_type 已存在: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_voice_style TEXT DEFAULT \'standard\'');
      } catch (e) {
        debugPrint('列 reminder_voice_style 已存在: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_voice_speed TEXT DEFAULT \'normal\'');
      } catch (e) {
        debugPrint('列 reminder_voice_speed 已存在: $e');
      }

      // 习惯表添加语音类型和风格字段
      try {
        await db.execute(
            'ALTER TABLE habits ADD COLUMN voice_type TEXT DEFAULT \'neutral\'');
      } catch (e) {
        debugPrint('列 voice_type 已存在: $e');
      }
      try {
        await db.execute(
            'ALTER TABLE habits ADD COLUMN voice_style TEXT DEFAULT \'standard\'');
      } catch (e) {
        debugPrint('列 voice_style 已存在: $e');
      }

      debugPrint('任务语音提醒字段添加成功');
    }

    // 版本7 -> 版本8: 添加自定义语音文件路径字段
    if (oldVersion < 8) {
      // 任务表添加自定义语音路径
      try {
        await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminder_custom_voice_path TEXT');
      } catch (e) {
        debugPrint('列 reminder_custom_voice_path 已存在: $e');
      }

      // 习惯表添加自定义语音路径
      try {
        await db.execute(
            'ALTER TABLE habits ADD COLUMN custom_voice_path TEXT');
      } catch (e) {
        debugPrint('列 custom_voice_path 已存在: $e');
      }

      debugPrint('自定义语音路径字段添加成功');
    }

    // 版本8 -> 版本9: 统一任务语音提醒默认开启
    if (oldVersion < 9) {
      try {
        await db.execute('''
          UPDATE tasks
          SET reminder_voice_enabled = 1
          WHERE reminder_minutes IS NOT NULL
            AND due_time IS NOT NULL
            AND status IN (0, 1)
            AND (reminder_voice_enabled IS NULL OR reminder_voice_enabled = 0)
        ''');
        debugPrint('任务语音提醒默认开关已修复');
      } catch (e) {
        debugPrint('修复任务语音提醒默认开关失败: $e');
      }
    }

    // 确保性能索引存在（不升级 schema version）
    try {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tasks_status_due_time ON tasks(status, due_time)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, completed_at)');
      debugPrint('性能索引已创建/确认');
    } catch (e) {
      debugPrint('创建性能索引失败: $e');
    }
  }

  // ==================== 任务相关操作 ====================

  /// 插入任务
  Future<void> insertTask(Task task) async {
    final db = await database;
    debugPrint('===== DatabaseHelper.insertTask =====');
    debugPrint('任务ID: ${task.id}');
    debugPrint('任务标题: ${task.title}');
    debugPrint('截止时间: ${task.dueTime}');
    debugPrint('状态: ${task.status}');

    final result = await db.insert(
      'tasks',
      task.toJson(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );

    debugPrint('插入结果: $result (行ID)');

    // 验证插入
    final savedTask = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    debugPrint('数据库验证: 找到 ${savedTask.length} 条匹配记录');
    debugPrint('====================================');
  }

  /// 获取所有任务
  Future<List<Task>> getAllTasks() async {
    final db = await database;
    debugPrint('===== DatabaseHelper.getAllTasks 开始 =====');

    // 先查询总数量
    final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM tasks')) ??
        0;
    debugPrint('数据库中的任务总数: $total');

    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      orderBy: 'created_at DESC',
    );

    debugPrint('查询到的任务记录数: ${maps.length}');

    if (maps.isNotEmpty) {
      debugPrint('前3个任务ID和标题:');
      for (int i = 0; i < maps.length && i < 3; i++) {
        debugPrint('  ${i + 1}. ID: ${maps[i]['id']}, 标题: ${maps[i]['title']}');
      }
    }

    debugPrint('===== DatabaseHelper.getAllTasks 完成 =====');

    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  /// 获取今日任务
  Future<List<Task>> getTodayTasks() async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'due_time >= ? AND due_time < ? AND status != ?',
      whereArgs: [
        todayStart.toIso8601String(),
        todayEnd.toIso8601String(),
        TaskStatus.completed.index,
      ],
      orderBy: 'priority DESC, due_time ASC',
    );
    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  /// 获取逾期任务
  Future<List<Task>> getOverdueTasks() async {
    final db = await database;
    final now = DateTime.now();

    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'due_time < ? AND status != ? AND status != ?',
      whereArgs: [
        now.toIso8601String(),
        TaskStatus.completed.index,
        TaskStatus.cancelled.index,
      ],
      orderBy: 'due_time ASC',
    );
    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  /// 根据状态获取任务
  Future<List<Task>> getTasksByStatus(TaskStatus status) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'status = ?',
      whereArgs: [status.index],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  /// 更新任务
  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update(
      'tasks',
      task.toJson(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// 删除任务
  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量删除任务
  Future<void> deleteTasks(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'tasks',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// 搜索任务
  Future<List<Task>> searchTasks(String keyword) async {
    final db = await database;
    final escaped = keyword.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'title LIKE ? OR content LIKE ?',
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  // ==================== 标签相关操作 ====================

  /// 插入标签
  Future<void> insertTag(Tag tag) async {
    final db = await database;
    await db.insert(
      'tags',
      tag.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有标签
  Future<List<Tag>> getAllTags() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tags',
      orderBy: 'sort_order ASC',
    );
    return List.generate(maps.length, (i) => Tag.fromJson(maps[i]));
  }

  /// 更新标签
  Future<void> updateTag(Tag tag) async {
    final db = await database;
    await db.update(
      'tags',
      tag.toJson(),
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  /// 删除标签
  Future<void> deleteTag(String id) async {
    final db = await database;
    await db.delete(
      'tags',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== 统计相关操作 ====================

  /// 获取任务统计
  Future<Map<String, int>> getTaskStats() async {
    final db = await database;

    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks'),
        ) ??
        0;

    final completed = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE status = ?',
              [TaskStatus.completed.index]),
        ) ??
        0;

    final pending = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE status = ?',
              [TaskStatus.pending.index]),
        ) ??
        0;

    final inProgress = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM tasks WHERE status = ?',
              [TaskStatus.inProgress.index]),
        ) ??
        0;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final overdue = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE due_time < ? AND status != ? AND status != ?',
            [now.toIso8601String(), TaskStatus.completed.index, TaskStatus.cancelled.index],
          ),
        ) ??
        0;

    return {
      'total': total,
      'completed': completed,
      'pending': pending,
      'inProgress': inProgress,
      'overdue': overdue,
    };
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      try {
        await _database!.close();
        _database = null;
        debugPrint('数据库已关闭');
      } catch (e) {
        debugPrint('关闭数据库失败: $e');
      }
    }
  }

  /// 重置数据库连接（用于应用重启时）
  Future<void> resetConnection() async {
    debugPrint('===== DatabaseHelper.resetConnection 开始 =====');

    try {
      // 如果数据库已打开，先关闭
      if (_database != null) {
        try {
          debugPrint('正在关闭现有数据库连接...');
          await _database!.close();
          debugPrint('数据库连接已关闭');
        } catch (e) {
          debugPrint('关闭数据库连接时出错（可能已经关闭）: $e');
        }
        _database = null;
        debugPrint('数据库引用已清空');
      } else {
        debugPrint('数据库连接为空，无需关闭');
      }

      // 重置初始化锁，防止下次访问时使用旧的 Future
      _databaseInitLock = null;
      debugPrint('数据库初始化锁已重置');

      // 清除任何缓存的查询结果
      debugPrint('清除数据库缓存...');

      debugPrint('===== DatabaseHelper.resetConnection 完成 =====');
      debugPrint('下次访问数据库时将重新建立连接');
    } catch (e) {
      debugPrint('重置数据库连接失败: $e');
      // 即使出错，也要确保_database为null
      _database = null;
      _databaseInitLock = null;
      rethrow;
    }
  }

  /// 获取数据库路径（用于调试）
  Future<String> getDatabasePath() async {
    return join(await getDatabasesPath(), 'smart_task_assistant.db');
  }

  /// 检查数据库文件是否存在
  Future<bool> databaseExists() async {
    final path = await getDatabasePath();
    try {
      return await databaseFactory.databaseExists(path);
    } catch (e) {
      debugPrint('检查数据库存在性失败: $e');
      return false;
    }
  }

  // ==================== 习惯相关操作 ====================

  /// 插入习惯
  Future<void> insertHabit(Habit habit) async {
    final db = await database;
    await db.insert(
      'habits',
      habit.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('习惯已插入: ${habit.title}');
  }

  /// 获取所有习惯
  Future<List<Habit>> getAllHabits() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'habits',
      orderBy: 'sort_order ASC',
    );
    return List.generate(maps.length, (i) => Habit.fromJson(maps[i]));
  }

  /// 获取启用的习惯
  Future<List<Habit>> getActiveHabits() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'habits',
      where: 'is_enabled = ?',
      whereArgs: [1],
      orderBy: 'sort_order ASC',
    );
    return List.generate(maps.length, (i) => Habit.fromJson(maps[i]));
  }

  /// 更新习惯
  Future<void> updateHabit(Habit habit) async {
    final db = await database;
    await db.update(
      'habits',
      habit.toJson(),
      where: 'id = ?',
      whereArgs: [habit.id],
    );
  }

  /// 删除习惯
  Future<void> deleteHabit(String id) async {
    final db = await database;
    await db.delete(
      'habits',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// ==================== 习惯日志相关操作 ====================

  /// 插入习惯日志
  Future<void> insertHabitLog(HabitLog log) async {
    final db = await database;
    await db.insert(
      'habit_logs',
      log.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取习惯的所有日志
  Future<List<HabitLog>> getHabitLogs(String habitId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'habit_logs',
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'completed_at DESC',
    );
    return List.generate(maps.length, (i) => HabitLog.fromJson(maps[i]));
  }

  /// 获取所有日志（按日期分组）
  Future<Map<String, List<HabitLog>>> getAllLogsByDate() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'habit_logs',
      orderBy: 'completed_at DESC',
    );

    final Map<String, List<HabitLog>> logsByDate = {};
    for (var map in maps) {
      final log = HabitLog.fromJson(map);
      final date = DateTime(log.completedAt.year, log.completedAt.month, log.completedAt.day);
      final dateKey = date.toIso8601String();
      logsByDate.putIfAbsent(dateKey, () => []).add(log);
    }
    return logsByDate;
  }

  /// 获取今日的日志
  Future<List<HabitLog>> getTodayLogs() async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final List<Map<String, dynamic>> maps = await db.query(
      'habit_logs',
      where: 'completed_at >= ? AND completed_at < ?',
      whereArgs: [todayStart.toIso8601String(), todayEnd.toIso8601String()],
      orderBy: 'completed_at DESC',
    );
    return List.generate(maps.length, (i) => HabitLog.fromJson(maps[i]));
  }

  /// 获取习惯今日完成数量
  Future<int> getHabitTodayCount(String habitId) async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT SUM(count) FROM habit_logs WHERE habit_id = ? AND completed_at >= ? AND completed_at < ? AND status = 0',
        [habitId, todayStart.toIso8601String(), todayEnd.toIso8601String()],
      ),
    );
    return result ?? 0;
  }

  /// 批量获取习惯今日完成数量（单次 SQL 查询）
  Future<Map<String, int>> getHabitTodayCountsBatch(List<String> habitIds) async {
    if (habitIds.isEmpty) return {};
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final placeholders = List.filled(habitIds.length, '?').join(',');
    final results = await db.rawQuery(
      'SELECT habit_id, SUM(count) as total FROM habit_logs '
      'WHERE habit_id IN ($placeholders) AND completed_at >= ? AND completed_at < ? AND status = 0 '
      'GROUP BY habit_id',
      [...habitIds, todayStart.toIso8601String(), todayEnd.toIso8601String()],
    );

    final Map<String, int> counts = {};
    for (final row in results) {
      counts[row['habit_id'] as String] = (row['total'] as int?) ?? 0;
    }
    // 确保所有 habitId 都有值
    for (final id in habitIds) {
      counts.putIfAbsent(id, () => 0);
    }
    return counts;
  }

  /// 清除习惯今日日志（达标后重置）
  Future<void> clearHabitTodayLogs(String habitId) async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    await db.delete(
      'habit_logs',
      where: 'habit_id = ? AND completed_at >= ? AND completed_at < ?',
      whereArgs: [habitId, todayStart.toIso8601String(), todayEnd.toIso8601String()],
    );
  }

  /// 删除习惯的所有日志
  Future<void> deleteHabitLogs(String habitId) async {
    final db = await database;
    await db.delete(
      'habit_logs',
      where: 'habit_id = ?',
      whereArgs: [habitId],
    );
  }
}
