# Habit Management Backend Integration

## Overview

Integrate the habit management functionality into the task_server backend to provide centralized data storage, synchronization across devices, and statistics tracking for the habit tracking feature recently added to the Flutter app.

## Problem Statement

The Flutter app currently implements habit management with local SQLite storage. This creates several limitations:

1. **No cross-device synchronization**: Habit data exists only on individual devices
2. **No centralized statistics**: Historical tracking and analytics are device-local
3. **Data loss risk**: If app is uninstalled or device is lost, all habit data is lost
4. **No backup/recovery**: No mechanism to restore habit data

## Scope

### In Scope

1. **Data Models**: Add `Habit` and `HabitLog` models to backend
2. **CRUD Operations**: Full habit management (create, read, update, delete, toggle)
3. **Completion Tracking**: Habit completion/skipping with timestamps
4. **Statistics**: Progress calculations and historical data
5. **Sync Integration**: Device-based synchronization (similar to Tasks)
6. **Preset Habits**: Server-side defaults for new users

### Out of Scope

- Real-time notifications (handled by Flutter app with local reminders)
- TTS/voice functionality (client-side only)
- Social features (sharing habits, leaderboards)
- Advanced analytics beyond basic statistics

## Data Model Design

### Habit Model

```go
type Habit struct {
    ID           uint      `gorm:"primarykey" json:"id"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
    DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
    UserID       uint      `gorm:"not null;index" json:"user_id"`
    User         User      `json:"user,omitempty"`

    // Identification
    HabitID      string    `gorm:"uniqueIndex:idx_user_habit_id;not null" json:"habit_id"` // Client-generated UUID
    Title        string    `gorm:"not null" json:"title"`

    // Target & Unit
    TargetCount  int       `gorm:"default:1" json:"target_count"`
    Unit         string    `gorm:"default:'次'" json:"unit"`

    // Trigger Configuration
    TriggerType  string    `gorm:"default:'interval'" json:"trigger_type"` // interval/fixed
    IntervalMinutes *int   `json:"interval_minutes"`
    FixedTime     string   `json:"fixed_time"` // HH:mm format
    ScheduleType  string    `gorm:"default:'weekdays'" json:"schedule_type"` // weekdays/daily

    // UI Settings
    IconCode     int       `json:"icon_code"` // Unicode code point
    SortOrder    int       `gorm:"default:0" json:"sort_order"`
    IsEnabled    bool      `gorm:"default:true" json:"is_enabled"`

    // Reminder Settings
    SoundEnabled   bool `gorm:"default:true" json:"sound_enabled"`
    VibrationEnabled bool `gorm:"default:true" json:"vibration_enabled"`
    VoiceEnabled   bool `gorm:"default:false" json:"voice_enabled"`
    VoiceText      *string `json:"voice_text"`
    VoiceSpeed     string `gorm:"default:'normal'" json:"voice_speed"` // slow/normal/fast

    // Clock-specific Fields
    ReferenceTime  *string `json:"reference_time"` // HH:mm for clock habits
    AdvanceMinutes *int    `json:"advance_minutes"` // Minutes before reference time

    // Sync
    DeviceID      string    `gorm:"index" json:"device_id"`
    SyncedAt      time.Time `json:"synced_at"`
}
```

### HabitLog Model

```go
type HabitLog struct {
    ID           uint      `gorm:"primarykey" json:"id"`
    CreatedAt    time.Time `json:"created_at"`
    UpdatedAt    time.Time `json:"updated_at"`
    UserID       uint      `gorm:"not null;index" json:"user_id"`
    User         User      `json:"user,omitempty"`

    HabitID      string    `gorm:"not null;index:idx_habit_date" json:"habit_id"`
    Count        int       `gorm:"default:1" json:"count"`
    Status       int       `gorm:"default:0" json:"status"` // 0: completed, 1: skipped
    CompletedAt  time.Time `gorm:"index:idx_habit_date;not null" json:"completed_at"`

    // Sync
    DeviceID      string    `gorm:"index" json:"device_id"`
}
```

### Habit Statistics

```go
type HabitStats struct {
    TodayProgress int     `json:"today_progress"`      // Count completed today
    TargetCount   int     `json:"target_count"`        // Daily target
    Percentage    int     `json:"percentage"`          // Progress %
    StreakDays   int     `json:"streak_days"`         // Consecutive days completed
    LastCompleted *time.Time `json:"last_completed"`
}

type HabitHistoryResponse struct {
    Date        string `json:"date"`        // YYYY-MM-DD
    Count       int    `json:"count"`       // Total completed
    Status      string `json:"status"`      // completed/partial/skipped
}
```

## API Design

### Habit Endpoints

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v1/habits` | Create habit | JWT |
| GET | `/api/v1/habits` | List habits (paginated) | JWT |
| GET | `/api/v1/habits/:habit_id` | Get habit details | JWT |
| PUT | `/api/v1/habits/:habit_id` | Update habit | JWT |
| DELETE | `/api/v1/habits/:habit_id` | Delete habit | JWT |
| PATCH | `/api/v1/habits/:habit_id/toggle` | Toggle enabled status | JWT |

### Habit Log Endpoints

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | `/api/v1/habits/:habit_id/logs` | Record completion/skip | JWT |
| GET | `/api/v1/habits/:habit_id/logs` | Get habit logs (paginated) | JWT |
| GET | `/api/v1/habits/:habit_id/stats` | Get habit statistics | JWT |
| GET | `/api/v1/habits/:habit_id/history` | Get completion history | JWT |

### Bulk Operations

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| GET | `/api/v1/habits/today` | Get all habits with today's progress | JWT |
| POST | `/api/v1/habits/sync` | Sync habits from device | JWT |

## Implementation Plan

### Phase 1: Data Layer

1. Create `internal/model/habit.go`
   - Define `Habit` struct
   - Define `HabitLog` struct
   - Define request/response DTOs
   - Add GORM tags for indexes

2. Create `internal/repository/habit_repository.go`
   - `Create(habit *Habit) error`
   - `FindByUserID(userID uint) ([]*Habit, error)`
   - `FindByID(id uint, userID uint) (*Habit, error)`
   - `FindByHabitID(habitID string, userID uint) (*Habit, error)`
   - `Update(habit *Habit) error`
   - `Delete(id uint, userID uint) error`
   - `ToggleEnabled(habitID string, userID uint) error`
   - `UpsertByDeviceID(habit *Habit) error` (for sync)

3. Create `internal/repository/habit_log_repository.go`
   - `Create(log *HabitLog) error`
   - `FindByHabitID(habitID string, userID uint, pagination) ([]*HabitLog, error)`
   - `GetTodayCount(habitID string, userID uint) (int, error)`
   - `GetDateRangeStats(habitID string, userID uint, start, end time.Time) ([]*HabitLog, error)`
   - `CalculateStreak(habitID string, userID uint) (int, error)`

### Phase 2: Service Layer

4. Create `internal/service/habit_service.go`
   - Business logic for habit CRUD
   - Ownership verification
   - Conflict resolution for sync
   - Validation (e.g., trigger type requires corresponding fields)

5. Create `internal/service/habit_log_service.go`
   - Recording completion/skipped
   - Statistics calculation
   - Streak calculation algorithm

### Phase 3: API Layer

6. Create `internal/api/handler/habit_handler.go`
   - HTTP handlers for all endpoints
   - Request validation
   - Response formatting
   - Error handling

7. Update `internal/api/router/router.go`
   - Register habit routes
   - Apply JWT middleware

### Phase 4: Initialization

8. Update `cmd/server/main.go`
   - Initialize HabitRepository
   - Initialize HabitService
   - Initialize HabitHandler
   - Run auto-migration for Habit/HabitLog tables

### Phase 5: Preset Habits

9. Create `internal/service/preset_habits.go` or similar
   - Define server-side default habits
   - Method to initialize habits for new users
   - Option to reset to defaults

## Key Design Decisions

### 1. HabitID as String vs uint
**Decision**: Use string (client-generated UUID)

**Rationale**:
- Matches Flutter app implementation
- Enables offline-first design (clients can create IDs locally)
- Prevents conflicts during sync

### 2. Log Status as int vs enum
**Decision**: Use int (0=completed, 1=skipped)

**Rationale**:
- GORM-friendly
- Easy to query
- Matches Flutter implementation

### 3. Separate DeviceID field
**Decision**: Yes, add `device_id` to both models

**Rationale**:
- Enables last-write-wins conflict resolution
- Tracks origin of each record
- Consistent with Task model pattern

### 4. Trigger Time Calculation
**Decision**: Server does NOT calculate next trigger time

**Rationale**:
- Client handles all time-based triggers (TTS, notifications)
- Server stores configuration only
- Reduces complexity and timezone issues

### 5. Streak Calculation Algorithm
**Decision**: Server calculates streaks based on logs

**Rationale**:
- Centralized statistics
- Consistent across devices
- Can be extended with future analytics

**Algorithm**:
```
1. Get all unique dates with at least one "completed" log
2. Sort dates descending
3. Check if today has a completed log → streak starts from 0 or 1
4. Walk backwards through dates
5. Increment streak while consecutive
6. Stop at first gap
```

## Success Criteria

- [ ] All CRUD operations functional for habits
- [ ] Habit logs can be recorded and retrieved
- [ ] Statistics API returns accurate progress percentages
- [ ] Streak calculation works correctly
- [ ] Device-based sync prevents data loss
- [ ] API responses match Flutter app expectations
- [ ] Auto-migration creates tables successfully
- [ ] JWT authentication protects all endpoints
- [ ] Unit tests for repository layer
- [ ] Integration tests for API endpoints

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sync conflicts | High | Implement last-write-wins based on `synced_at` timestamp |
| Large log tables | Medium | Add indexes on `(habit_id, completed_at)`, consider archiving old logs |
| Timezone issues | Low | Store all times in UTC, let client handle conversion |
| Performance with many users | Medium | Add caching for stats, consider pagination for history |

## Future Considerations

- Historical analytics (weekly/monthly/yearly trends)
- Habit templates/achievements
- Social features (compare with friends)
- Export/import habit data
- Habit recommendations based on patterns

## Related Artifacts

- Flutter Habit Model: `lib/models/habit.dart`
- Flutter HabitLog Model: `lib/models/habit_log.dart`
- Flutter HabitProvider: `lib/providers/habit_provider.dart`
- Backend Architecture: `CLAUDE.md`