# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Smart Task Assistant is a cross-platform Flutter app for intelligent task management with AI-powered natural language parsing, task suggestions, reminders, and habit tracking. It supports Android, iOS, Web, and Desktop platforms.

**Key Technology Stack:**
- Flutter 3.2.0+, Dart 3.2.0+
- Provider 6.1.1 for state management
- SQLite (sqflite) for local data persistence
- flutter_tts for text-to-speech (habit/task reminders)
- Multi-platform conditional imports for platform-specific features

**Backend Service (task_server):**
- Go 1.21+, Gin Web Framework
- PostgreSQL 15, Redis 7
- Docker Compose for deployment

**Current Version:** 1.3.33+62

## Common Commands

### Development
```bash
flutter pub get              # Install dependencies
flutter run                  # Run on connected device/emulator
flutter run -d windows       # Run on specific platform
flutter run -d chrome
flutter run -d android
```

### Building
```bash
flutter build apk --release         # Android APK
flutter build appbundle --release   # Android App Bundle
flutter build web --release         # Web
flutter build windows --release     # Windows desktop
```

### Testing & Analysis
```bash
flutter test                                  # Run all tests
flutter test test/task_distribution_service_test.dart  # Run specific test
flutter analyze                               # Analyze code for issues
dart format .                                 # Format code
```

## Architecture

### Layer Structure
```
lib/
├── main.dart                    # App entry point, MultiProvider setup, AppSettings
├── database/
│   ├── database_helper.dart     # SQLite singleton (schema v8), migration, connection management
│   ├── storage_service.dart     # Abstract storage interface
│   ├── storage_service_native.dart  # SQLite implementation (mobile/desktop)
│   └── storage_service_web.dart     # IndexedDB implementation (web)
├── models/                      # Domain models
│   ├── task.dart                # Task entity with status/priority enums
│   ├── tag.dart                 # Tag entity
│   ├── habit.dart               # Habit entity with reminder/voice settings
│   ├── habit_log.dart           # Habit completion log
│   ├── task_suggestion.dart     # AI-suggested tasks
│   ├── task_distribution.dart   # Task distribution analysis
│   └── city.dart                # CityInfo model for weather service
├── providers/                   # State management (ChangeNotifier + Provider)
│   ├── task_provider.dart       # Task CRUD, filtering, statistics
│   ├── task_provider_optimized.dart  # Cached/optimized task provider variant
│   ├── settings_provider.dart   # App settings, AI config sync
│   ├── habit_provider.dart      # Habit CRUD, progress tracking, completion logging
│   └── task_distribution_provider.dart  # Task distribution state
├── services/
│   ├── ai_service.dart          # Natural language parsing, chat, suggestions
│   ├── reminder_service.dart    # Notification scheduling (platform-conditional)
│   ├── tts_service.dart         # TTS singleton: voice synthesis + custom audio file playback
│   ├── habit_service.dart       # Habit time calculation, trigger logic
│   ├── clipboard_monitor_service.dart  # Clipboard watching (platform-conditional)
│   ├── weather_service.dart     # Weather API with city model
│   └── task_distribution_service.dart  # Task analysis algorithms
├── screens/
│   ├── home_screen.dart         # 5-tab bottom nav: Today, All Tasks, Habits, Stats, Settings
│   ├── add_task_screen.dart     # Task creation/editing with voice file support
│   ├── habit_screen.dart        # Habit management list
│   ├── settings_screen.dart     # Configuration, AI setup
│   └── stats_screen.dart        # Analytics with charts
├── widgets/                     # Reusable components
│   ├── task_card.dart, habit_card.dart, quick_add_modal.dart
│   ├── habit_settings_dialog.dart, habit_reminder_dialog.dart
│   ├── ai_chat_dialog.dart, reminder_action_dialog.dart
│   ├── tag_management_dialog.dart, tag_create_dialog.dart, tag_edit_dialog.dart
│   ├── city_selector_dialog.dart, log_viewer_dialog.dart, stat_card.dart
├── theme/
│   └── app_theme.dart           # Light/Dark theme definitions
└── utils/
    ├── app_localizations.dart   # i18n (zh-CN default, en-US)
    ├── app_logger.dart          # Logging utilities
    ├── task_filter.dart         # Task filtering logic
    ├── bubble_sort.dart         # Sorting utilities
    └── platform_*.dart          # Platform-specific utilities (conditional imports)
```

### State Management Pattern
Uses **Provider** with `ChangeNotifier`:
- `TaskProvider`: Task CRUD, filtering, statistics
- `SettingsProvider`: App settings, AI configuration persistence (SharedPreferences)
- `HabitProvider`: Habit CRUD, progress tracking, completion logging
- `AppSettings` (global): Theme mode, locale, feature toggles

### Database Architecture
- **Singleton** `DatabaseHelper` with init lock to prevent concurrent initialization
- **Schema version 8** — tables: `tasks`, `tags`, `reminders`, `task_distributions`, `habits`, `habit_logs`
- Auto-reconnect on app resume via `WidgetsBindingObserver`
- Version 8 added custom voice file fields (`custom_voice_path`) to tasks and habits

**Migration pattern:**
```dart
if (oldVersion < NEW_VERSION) {
  await db.execute('CREATE TABLE ...');
  // or
  await db.execute('ALTER TABLE ... ADD COLUMN ...');
}
```
Increment `version` in `openDatabase()`, add to `_onCreate()` for fresh installs, add to `_onUpgrade()` for migrations.

### Platform-Specific Code
Conditional imports pattern:
```dart
import 'native_version.dart'
    if (dart.library.html) 'web_version.dart'
    if (dart.library.io) 'desktop_version.dart';
```
Key platform-specific modules:
- `storage_service_*`: SQLite (native) vs IndexedDB (web)
- `reminder_service_*`: Local notifications (native) vs stub (web)
- `clipboard_monitor_service_*`: Native clipboard API vs web clipboard
- `platform_file_*`: File pickers (native) vs web file inputs

### AI Service
- **Local rule engine** (default, no API key required)
- **External AI providers**: OpenAI, 通义千问, 智谱AI, Kimi, Ollama, Custom API
- Configuration in SharedPreferences via `SettingsProvider`
- Natural language parsing: time, priority, tags (# prefix), assignees (@ prefix)

### TTS Service
Singleton `TTSService` handles both text-to-speech and custom audio file playback:
- Uses `flutter_tts` for synthesis, `audioplayers` for custom voice files
- Supports male/female/neutral voices, configurable speech rate
- Tasks and habits can have `custom_voice_path` for personalized reminders

### Habit System
**Habit Types:** `habit_water` (interval, tracks completion), `habit_stretch` (interval, tracks completion), `habit_clock_in` / `habit_clock_out` (fixed-time, no completion tracking)

**Trigger Types:** `interval` (every X minutes, default start 9:00) | `fixed` (specific HH:mm)
**Schedule Types:** `weekdays` (Mon-Fri) | `daily`

### Home Screen Structure
5-tab bottom nav:
- **Today** (`_currentIndex = 0`): Progress card, weather, AI suggestions, overdue tasks
- **All Tasks** (`_currentIndex = 1`): Search + filter chips + task list
- **Habits** (`_currentIndex = 2`): Habit management with progress tracking
- **Stats** (`_currentIndex = 3`): Analytics dashboard
- **Settings** (`_currentIndex = 4`): App configuration

## Important Development Notes

- **Database connections** are reset on app resume — always check `_database != null` before use
- **i18n**: Default `zh-CN`, also `en-US`. All UI text must use `AppLocalizations`
- **Color API**: Use `Colors.white.withValues(alpha: 0.5)` instead of deprecated `withOpacity(0.5)`
- **Notification sounds**: `assets/sounds/notification.mp3`, vibration 3x300ms with 100ms gaps
- **Persistent reminders**: Continue until dismissed or 1 hour past deadline

### Adding New Features
1. Add model to `models/`
2. Update `database_helper.dart` schema (increment version, update `_onCreate` + `_onUpgrade`)
3. Add service methods to `services/`
4. Create/update provider in `providers/`
5. Add UI in `widgets/` or `screens/`
6. Register provider in `main.dart` `MultiProvider`

## Backend Service (task_server)

Located at `../task_server`. Provides RESTful API for the Flutter app.

```bash
cd ../task_server
docker-compose up -d          # Start (PostgreSQL + Redis + App)
go run cmd/server/main.go     # Local development
```

**API Base URL**: `http://localhost:8080/api/v1`
- `POST /api/v1/auth/register` - Register
- `POST /api/v1/auth/login` - Login (returns JWT)
- `GET/POST /api/v1/tasks` - List/Create tasks
- `PUT/DELETE /api/v1/tasks/{id}` - Update/Delete task
- `GET /api/v1/tasks/stats` - Task statistics

**Environment**: `task_server/configs/.env` — server, DB, Redis, JWT config.

## Version Management
- Current: `1.3.33+62` (in `pubspec.yaml`)
- APK output: `OUTPUT/智能任务助手_v{version}.apk`
