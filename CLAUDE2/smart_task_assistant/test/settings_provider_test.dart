/// SettingsProvider 持久化与免打扰逻辑测试
///
/// 用 SharedPreferences mock 验证「保存 → 重新加载」往返一致，
/// 以及 isQuietTime 的跨天区间判断。
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_task_assistant/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('设置持久化往返', () {
    test('保存后重新加载，各字段一致（原生 KV 路径）', () async {
      SharedPreferences.setMockInitialValues({});
      final p1 = SettingsProvider();
      await p1.loadSettings();

      p1.setThemeMode(ThemeMode.dark);
      p1.setNotificationsEnabled(false);
      p1.setQuietHoursEnabled(true);
      p1.setQuietHours(startHour: 1, endHour: 5);
      p1.setTaskReminderSoundEnabled(false);
      p1.setAutoCompleteParentTask(false);
      p1.setTtsVolume(0.5);

      // 新实例重新加载（模拟进程重启）
      final p2 = SettingsProvider();
      await p2.loadSettings();

      expect(p2.themeMode, ThemeMode.dark);
      expect(p2.notificationsEnabled, isFalse);
      expect(p2.quietHoursEnabled, isTrue);
      expect(p2.quietHoursStart, 1);
      expect(p2.quietHoursEnd, 5);
      expect(p2.taskReminderSoundEnabled, isFalse);
      expect(p2.autoCompleteParentTask, isFalse);
      expect(p2.ttsVolume, 0.5);
    });

    test('未保存过的键加载后保持默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider();
      await p.loadSettings();

      expect(p.themeMode, ThemeMode.system);
      expect(p.notificationsEnabled, isTrue);
      expect(p.clipboardMonitorEnabled, isFalse);
      expect(p.quietHoursEnabled, isFalse);
      expect(p.quietHoursStart, 22);
      expect(p.ttsVolume, 0.9);
    });
  });

  group('isQuietTime 免打扰判断', () {
    SettingsProvider providerWith(int start, int end) {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider();
      p.setQuietHoursEnabled(true);
      p.setQuietHours(startHour: start, endHour: end);
      return p;
    }

    test('同日区间（22→7 跨夜）：23 点在免打扰内', () {
      final p = providerWith(22, 7);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 23)), isTrue);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 12)), isFalse);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 6, 59)), isTrue);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 7)), isFalse);
    });

    test('正向区间（9→12）', () {
      final p = providerWith(9, 12);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 9)), isTrue);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 11, 59)), isTrue);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 12)), isFalse);
    });

    test('起止相等 = 全天免打扰', () {
      final p = providerWith(8, 8);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 3)), isTrue);
      expect(p.isQuietTime(DateTime(2026, 10, 1, 22)), isTrue);
    });
  });
}
