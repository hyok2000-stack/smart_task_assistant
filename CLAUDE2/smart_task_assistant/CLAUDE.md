# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Smart Task Assistant is a cross-platform Flutter app for intelligent task management with AI-powered natural language parsing, task suggestions, and reminders. It supports Android, iOS, Web, and Desktop platforms.

**Key Technology Stack:**
- Flutter 3.2.0+, Dart 3.2.0+
- Provider 6.1.1 for state management
- SQLite (sqflite) for local data persistence
- Multi-Platform conditional imports for platform-specific features

**Backend Service (task_server):**
- Go 1.21+, Gin Web Framework
- PostgreSQL 15, Redis 7
- Docker Compose for deployment

**Current Version:** 1.3.15

## Common Commands

### Development
```bash
# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run on specific platform
flutter run -d android
flutter run -d ios
flutter run -d chrome
flutter run -d windows
flutter run -d macos
flutter run -d linux

# Hot reload (in running terminal)
# Press 'r' in terminal while app is running
```

### Building
```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Desktop builds
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

### Testing & Analysis
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/task_distribution_service_test.dart

# Analyze code for issues
flutter analyze

# Format code
dart format .
```

## Architecture

### Layer Structure
```
lib/
├── main.dart                    # App entry point, global providers setup
├── database/                    # Data persistence layer
│   ├── database_helper.dart     # SQLite singleton with connection management
│   ├── storage_service.dart     # Abstract storage interface
│   ├── storage_service_native.dart  # SQLite implementation (mobile/desktop)
│   └── storage_service_web.dart     # IndexedDB implementation (web)
├── models/                      # Domain models
│   ├── task.dart                # Task entity with status/priority enums
│   ├── tag.dart                 # Tag entity
│   ├── task_suggestion.dart     # AI-suggested tasks
│   └── task_distribution.dart   # Task distribution analysis
├── providers/                   # State management (Provider pattern)
│   ├── task_provider.dart       # Task CRUD, filtering, stats
│   ├── settings_provider.dart   # App settings, AI config sync
│   └── task_distribution_provider.dart  # Task distribution state
├── services/                    # Business logic
│   ├── ai_service.dart          # Natural language parsing, chat, suggestions
│   ├── reminder_service.dart    # Notification scheduling (platform-conditional)
│   ├── clipboard_monitor_service.dart  # Clipboard watching (platform-conditional)
│   ├── weather_service.dart     # Weather API integration
│   └── task_distribution_service.dart  # Task analysis algorithms
├── screens/                     # UI pages
│   ├── home_screen.dart         # Main task list with stats
│   ├── add_task_screen.dart     # Task creation/editing
│   ├── settings_screen.dart     # Configuration, AI setup
│   └── stats_screen.dart        # Analytics with charts
├── widgets/                     # Reusable components
│   ├── task_card.dart           # Task display with swipe actions
│   ├── ai_chat_dialog.dart      # AI assistant chat interface
│   ├── quick_add_modal.dart     # Fast task creation modal
│   └── reminder_action_dialog.dart  # Reminder response UI
├── theme/                       # Theming
│   └── app_theme.dart           # Light/Dark theme definitions
└── utils/                       # Utilities
    ├── app_localizations.dart   # i18n (zh-CN, en-US)
    ├── app_logger.dart          # Logging utilities
    └── platform_*.dart          # Platform-specific utilities (conditional)
```

### State Management Pattern
- Uses **Provider** pattern with `ChangeNotifier`
- Three main providers:
  - `TaskProvider`: Task CRUD operations, filtering, statistics
  - `SettingsProvider`: App settings, AI configuration persistence
  - `AppSettings` (global): Theme mode, locale, feature toggles

### Database Architecture
- **Singleton pattern** for `DatabaseHelper`
- Auto-reconnect on app resume (handles lifecycle events)
- Tables: `tasks`, `tags`, `reminders`
- Version 4 schema with migration support

### Platform-Specific Code
Conditional imports are used for platform-specific features:

```dart
// Example pattern
import 'native_version.dart'
    if (dart.library.html) 'web_version.dart'
    if (dart.library.io) 'desktop_version.dart';
```

**Key platform-specific modules:**
- `storage_service_*`: SQLite (native) vs IndexedDB (web)
- `reminder_service_*`: Local notifications (native) vs Web Push API (web)
- `clipboard_monitor_service_*`: Native clipboard API vs web clipboard
- `platform_file_*`: File pickers (native) vs web file inputs

### AI Service
- **Local rule engine** (default, no API key required)
- **External AI providers** via API:
  - OpenAI, 通义千问, 智谱AI, Kimi, Ollama, Custom API
- Configuration stored in SharedPreferences via `SettingsProvider`
- Natural language parsing for: time, priority, tags (@ mentions), assignees

### Natural Language Parsing Examples
```
"明天下午3点开会 #工作 @张三 紧急"
→ title: "开会", due: tomorrow 3pm, tag: "工作", assignee: "张三", priority: high
```

### App Lifecycle Handling
The app properly handles state transitions using `WidgetsBindingObserver`:
- **Resumed**: Reloads data with database reconnect
- **Paused**: Saves state
- **Detached**: Closes all singleton connections

## Important Development Notes

### Database Connection Management
- Database connections are reset when app resumes from background
- Always check `_database != null` and validity before use
- Call `resetDatabaseConnection()` on provider when needed

### Internationalization
- Default locale: `zh-CN` (Chinese)
- Supported locales: `zh-CN`, `en-US`
- All UI text should use `AppLocalizations` for i18n support

### Error Handling
- Use `AppLogger` for consistent logging
- Catch and display errors gracefully in UI
- Provider `error` property accessible to widgets

### Platform Limitations
- **Web**: No local notifications (uses web push), limited file picker
- **Desktop**: Not all mobile features available (e.g., vibration)
- **Clipboard monitoring**: Only works on platforms with proper permissions

### Notification Sounds
- Default sound file: `assets/sounds/notification.mp3`
- Add custom sound by placing MP3 file in `assets/sounds/`
- Vibration: 3 pulses of 300ms with 100ms gaps
- Persistent reminders continue until user dismisses or 1 hour after deadline

### Adding New Features
1. Add model to `models/`
2. Update `database_helper.dart` schema + migrations
3. Add service method to `services/`
4. Update `TaskProvider` or create new provider
5. Add UI in `widgets/` or `screens/`

### Home Screen Structure
The main `home_screen.dart` uses a bottom navigation with 4 tabs:
- **Today** (`_currentIndex = 0`): Today's tasks with progress card, weather, AI suggestions, overdue tasks
- **All Tasks** (`_currentIndex = 1`): Searchable task list with filters
- **Stats** (`_currentIndex = 2`): Analytics dashboard
- **Settings** (`_currentIndex = 3`): App configuration

Key components:
- `_showNotifications()`: Shows overdue tasks in a bottom sheet with `Column` + `Expanded` structure
- `_buildTodayPage()`: Main view with `CustomScrollView` containing multiple `SliverToBoxAdapter` sections
- `_buildAllTasksPage()`: Search + filter chips + task list
- `_buildProgressCard()`: Circular progress indicator with compact stats
- `_buildAISuggestionCard()`: Gradient card with AI recommendation
- `_buildCompletedSection()`: Expandable section for completed tasks

### Color API Migration
Replace deprecated `withOpacity()` with `withValues(alpha:)`:
```dart
// Old (deprecated)
Colors.white.withOpacity(0.5)

// New
Colors.white.withValues(alpha: 0.5)
```

## Backend Service (task_server)

The backend service provides RESTful API support for the Flutter app.

### Quick Start (Docker Compose)
```bash
# Navigate to task_server directory
cd ../task_server

# Start all services (PostgreSQL, Redis, App)
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Local Development
```bash
cd ../task_server
go mod download
go run cmd/server/main.go
```

### API Endpoints
- **Base URL**: `http://localhost:8080/api/v1`
- **Health Check**: `http://localhost:8080/health`

Key endpoints:
- `POST /api/v1/auth/register` - User registration
- `POST /api/v1/auth/login` - User login (returns JWT token)
- `GET /api/v1/tasks` - List tasks (supports pagination, filtering)
- `POST /api/v1/tasks` - Create task
- `PUT /api/v1/tasks/{id}` - Update task
- `DELETE /api/v1/tasks/{id}` - Delete task
- `GET /api/v1/tasks/stats` - Task statistics

### Environment Variables
Located in `task_server/configs/.env`:
- `SERVER_HOST`, `SERVER_PORT` - Server binding
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` - PostgreSQL config
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_DB` - Redis config
- `JWT_SECRET` - JWT signing key

## Version Management
- Current version: `1.3.15`
- Update in `pubspec.yaml` (version field) and build output files
- APK builds saved to `OUTPUT/智能任务助手_v{version}.apk`