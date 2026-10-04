/// 回收站数据库往返测试（sqflite_ffi 桌面实现，无需真机）
///
/// 覆盖：快照入库 → 列表 → 恢复 → 彻底删除 → 30 天自动清理
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_task_assistant/database/database_helper.dart';
import 'package:smart_task_assistant/models/task.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Task buildTask(String id, String title) => Task(
        id: id,
        title: title,
        createdAt: DateTime(2026, 10, 1, 9),
        updatedAt: DateTime(2026, 10, 1, 9),
      );

  test('moveToTrash → getTrashEntries 能列出快照', () async {
    final db = DatabaseHelper();
    await db.moveToTrash(buildTask('trash-1', '被删除的任务'));

    final entries = await db.getTrashEntries();
    expect(entries, isNotEmpty);
    expect(entries.first['title'], '被删除的任务');
    expect(entries.first['payload'], contains('trash-1'));
  });

  test('restoreFromTrash：任务回插 + 快照清除', () async {
    final db = DatabaseHelper();
    await db.moveToTrash(buildTask('trash-2', '待恢复任务'));

    final entries = await db.getTrashEntries();
    final target = entries.firstWhere((e) => e['id'] == 'trash-2');

    final ok = await db.restoreFromTrash(target['id'] as String);
    expect(ok, isNotNull);

    // 恢复后任务重新出现在 tasks 表
    final all = await db.getAllTasks();
    final restored = all.where((t) => t.id == 'trash-2').toList();
    expect(restored, hasLength(1));
    expect(restored.first.title, '待恢复任务');

    // 快照已清除
    final after = await db.getTrashEntries();
    expect(after.where((e) => e['id'] == 'trash-2'), isEmpty);
  });

  test('purgeTrashItem 彻底删除单条快照', () async {
    final db = DatabaseHelper();
    await db.moveToTrash(buildTask('trash-3', '将被彻底删除'));

    await db.purgeTrashItem('trash-3');
    final entries = await db.getTrashEntries();
    expect(entries.where((e) => e['id'] == 'trash-3'), isEmpty);
  });

  test('超过 30 天的快照在列表加载时自动清理', () async {
    final db = DatabaseHelper();
    await db.moveToTrash(buildTask('trash-old', '一个月前的删除'));

    // 直接把 deleted_at 改成 31 天前
    final raw = await db.database;
    final oldDate =
        DateTime.now().subtract(const Duration(days: 31)).toIso8601String();
    await raw.update('task_trash', {'deleted_at': oldDate},
        where: 'id = ?', whereArgs: ['trash-old']);

    final entries = await db.getTrashEntries();
    expect(entries.where((e) => e['id'] == 'trash-old'), isEmpty);
  });

  test('emptyTrash 清空回收站', () async {
    final db = DatabaseHelper();
    await db.moveToTrash(buildTask('trash-4', 'a'));
    await db.moveToTrash(buildTask('trash-5', 'b'));
    await db.emptyTrash();
    expect(await db.getTrashEntries(), isEmpty);
  });
}
