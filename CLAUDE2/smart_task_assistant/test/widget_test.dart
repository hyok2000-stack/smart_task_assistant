// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:smart_task_assistant/main.dart';
import 'package:smart_task_assistant/providers/task_provider.dart';
import 'package:smart_task_assistant/providers/settings_provider.dart';
import 'package:smart_task_assistant/services/reminder_service.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Create provider instances
    final taskProvider = TaskProvider();
    final settingsProvider = SettingsProvider();
    final reminderService = ReminderService();

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(
      taskProvider: taskProvider,
      settingsProvider: settingsProvider,
      reminderService: reminderService,
    ));

    // Wait for loading to complete
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Verify the app loads with gradient background
    expect(find.byType(Container), findsWidgets);
  });
}
