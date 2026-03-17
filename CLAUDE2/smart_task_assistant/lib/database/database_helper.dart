import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';
import '../models/tag.dart';

/// 数据库帮助类
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  /// 获取数据库实例
  Future<Database> get database async {
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
      rethrow;
    }
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'smart_task_assistant.db');
    return await openDatabase(
      path,
      version: 3,
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
        reminder_dismissed INTEGER DEFAULT 0
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

    // 插入默认标签
    await _insertDefaultTags(db);
  }

  /// 插入默认标签
  Future<void> _insertDefaultTags(Database db) async {
    final defaultTags = Tag.getDefaultTags();

    for (var tag in defaultTags) {
      await db.insert('tags', tag.toJson());
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
      conflictAlgorithm: ConflictAlgorithm.replace,
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
      where: 'due_time < ? AND status != ?',
      whereArgs: [
        now.toIso8601String(),
        TaskStatus.completed.index,
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
    final db = await database;
    for (var id in ids) {
      await db.delete(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// 搜索任务
  Future<List<Task>> searchTasks(String keyword) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'title LIKE ? OR content LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%'],
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
            'SELECT COUNT(*) FROM tasks WHERE due_time < ? AND status != ?',
            [todayStart.toIso8601String(), TaskStatus.completed.index],
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

      // 清除任何缓存的查询结果
      debugPrint('清除数据库缓存...');

      debugPrint('===== DatabaseHelper.resetConnection 完成 =====');
      debugPrint('下次访问数据库时将重新建立连接');
    } catch (e) {
      debugPrint('重置数据库连接失败: $e');
      // 即使出错，也要确保_database为null
      _database = null;
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
}
