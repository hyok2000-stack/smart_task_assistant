# Habit Management Backend Integration - Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      CLIENT (Flutter App)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  Habit Card  │  │   Settings   │  │  Reminder    │              │
│  │    UI        │  │   Dialog     │  │   Service    │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
└─────────┼──────────────────┼──────────────────┼─────────────────────┘
          │                  │                  │
          │  HTTP/JSON       │  HTTP/JSON       │  Local Only
          │                  │                  │
┌─────────┴──────────────────┴──────────────────┴─────────────────────┐
│                        API LAYER                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │habit_handler │  │habit_log_    │  │habit_stats_  │              │
│  │  .go         │  │handler.go    │  │handler.go    │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
└─────────┼──────────────────┼──────────────────┼─────────────────────┘
          │                  │                  │
┌─────────┴──────────────────┴──────────────────┴─────────────────────┐
│                      SERVICE LAYER                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │habit_service │  │habit_log_    │  │preset_habits │              │
│  │  .go         │  │service.go    │  │.go          │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
└─────────┼──────────────────┼──────────────────┼─────────────────────┘
          │                  │                  │
┌─────────┴──────────────────┴──────────────────┴─────────────────────┐
│                    REPOSITORY LAYER                                 │
│  ┌──────────────┐  ┌──────────────┐                                 │
│  │habit_repo    │  │habit_log_    │                                 │
│  │  .go         │  │repo.go       │                                 │
│  └──────┬───────┘  └──────┬───────┘                                 │
└─────────┼──────────────────┼───────────────────────────────────────┘
          │                  │
          └────────┬─────────┘
                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        DATABASE LAYER                                │
│         PostgreSQL / SQLite (with GORM)                             │
│  ┌──────────────┐  ┌──────────────┐                                 │
│  │   habits     │  │  habit_logs  │                                 │
│  └──────────────┘  └──────────────┘                                 │
└─────────────────────────────────────────────────────────────────────┘
```

## Database Schema

### habits Table

```sql
CREATE TABLE habits (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    deleted_at TIMESTAMP,

    -- User & Identification
    user_id BIGINT NOT NULL,
    habit_id VARCHAR(36) NOT NULL,
    title VARCHAR(100) NOT NULL,

    -- Target & Unit
    target_count INTEGER NOT NULL DEFAULT 1,
    unit VARCHAR(10) NOT NULL DEFAULT '次',

    -- Trigger Configuration
    trigger_type VARCHAR(10) NOT NULL DEFAULT 'interval',
    interval_minutes INTEGER,
    fixed_time VARCHAR(5),
    schedule_type VARCHAR(10) NOT NULL DEFAULT 'weekdays',

    -- UI Settings
    icon_code INTEGER NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_enabled BOOLEAN NOT NULL DEFAULT true,

    -- Reminder Settings
    sound_enabled BOOLEAN NOT NULL DEFAULT true,
    vibration_enabled BOOLEAN NOT NULL DEFAULT true,
    voice_enabled BOOLEAN NOT NULL DEFAULT false,
    voice_text TEXT,
    voice_speed VARCHAR(10) NOT NULL DEFAULT 'normal',

    -- Clock-specific Fields
    reference_time VARCHAR(5),
    advance_minutes INTEGER,

    -- Sync
    device_id VARCHAR(50),
    synced_at TIMESTAMP NOT NULL,

    UNIQUE(user_id, habit_id)
);

CREATE INDEX idx_habits_user_id ON habits(user_id);
CREATE INDEX idx_habits_device_id ON habits(device_id);
CREATE INDEX idx_habits_is_enabled ON habits(is_enabled);
CREATE INDEX idx_habits_sort_order ON habits(sort_order);
```

### habit_logs Table

```sql
CREATE TABLE habit_logs (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,

    -- User & Habit
    user_id BIGINT NOT NULL,
    habit_id VARCHAR(36) NOT NULL,

    -- Completion Data
    count INTEGER NOT NULL DEFAULT 1,
    status INTEGER NOT NULL DEFAULT 0,
    completed_at TIMESTAMP NOT NULL,

    -- Sync
    device_id VARCHAR(50)
);

CREATE INDEX idx_habit_logs_user_id ON habit_logs(user_id);
CREATE INDEX idx_habit_logs_habit_id ON habit_logs(habit_id);
CREATE INDEX idx_habit_logs_habit_date ON habit_logs(habit_id, completed_at);
CREATE INDEX idx_habit_logs_device_id ON habit_logs(device_id);
```

## Repository Layer Design

### HabitRepository Interface

```go
type HabitRepository interface {
    // Basic CRUD
    Create(habit *model.Habit) error
    FindByID(id uint, userID uint) (*model.Habit, error)
    FindByHabitID(habitID string, userID uint) (*model.Habit, error)
    FindByUserID(userID uint) ([]*model.Habit, error)
    Update(habit *model.Habit) error
    Delete(id uint, userID uint) error

    // Toggle
    ToggleEnabled(habitID string, userID uint) error

    // Sync operations
    UpsertByDeviceID(habit *model.Habit) error
    FindByDeviceID(deviceID string, userID uint) ([]*model.Habit, error)

    // Batch operations
    BulkUpsert(habits []*model.Habit) error
}
```

### HabitLogRepository Interface

```go
type HabitLogRepository interface {
    // Basic CRUD
    Create(log *model.HabitLog) error
    FindByID(id uint, userID uint) (*model.HabitLog, error)

    // Query by habit
    FindByHabitID(habitID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error)
    GetTodayCount(habitID string, userID uint) (int, error)

    // Date range queries
    GetDateRangeLogs(habitID string, userID uint, start, end time.Time) ([]*model.HabitLog, error)
    GetDateRangeCount(habitID string, userID uint, start, end time.Time) (int, error)

    // History for stats
    GetUniqueCompletionDates(habitID string, userID uint, days int) ([]time.Time, error)

    // Sync operations
    UpsertByDeviceID(log *model.HabitLog) error
    FindByDeviceID(deviceID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error)
}
```

## Service Layer Design

### HabitService

```go
type HabitService struct {
    repo  HabitRepository
    logRepo HabitLogRepository
    preset *PresetHabitService
}

// Core Operations
func (s *HabitService) Create(userID uint, req *model.CreateHabitRequest) (*model.Habit, error)
func (s *HabitService) GetByID(id uint, userID uint) (*model.Habit, error)
func (s *HabitService) GetByHabitID(habitID string, userID uint) (*model.Habit, error)
func (s *HabitService) List(userID uint, req *model.ListHabitsRequest) (*model.ListHabitsResponse, error)
func (s *HabitService) Update(id uint, userID uint, req *model.UpdateHabitRequest) (*model.Habit, error)
func (s *HabitService) Delete(id uint, userID uint) error
func (s *HabitService) ToggleEnabled(habitID string, userID uint) error

// Sync Operations
func (s *HabitService) SyncFromDevice(userID uint, deviceID string, habits []*model.Habit) error
func (s *HabitService) InitializeDefaults(userID uint) error
```

### HabitLogService

```go
type HabitLogService struct {
    repo  HabitLogRepository
    habitRepo HabitRepository
}

// Logging
func (s *HabitLogService) LogCompletion(userID uint, habitID string, count int, status int) (*model.HabitLog, error)
func (s *HabitLogService) List(habitID string, userID uint, req *model.ListHabitLogsRequest) (*model.ListHabitLogsResponse, error)

// Statistics
func (s *HabitLogService) GetStats(habitID string, userID uint) (*model.HabitStats, error)
func (s *HabitService) CalculateStreak(habitID string, userID uint) (int, error)
func (s *HabitLogService) GetHistory(habitID string, userID uint, days int) ([]*model.HabitHistoryResponse, error)
```

## Statistics Calculation Algorithms

### Today Progress

```go
func (s *HabitLogService) GetTodayProgress(habitID string, userID uint) int {
    today := time.Now().UTC()
    startOfDay := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, time.UTC)
    endOfDay := startOfDay.Add(24 * time.Hour)

    // Count only completed logs (status = 0)
    count, _ := s.repo.GetDateRangeCount(
        habitID,
        userID,
        startOfDay,
        endOfDay,
        0, // status: completed only
    )
    return count
}
```

### Streak Calculation

```go
func (s *HabitLogService) CalculateStreak(habitID string, userID uint) int {
    // Get last 365 days of unique completion dates
    dates, _ := s.repo.GetUniqueCompletionDates(habitID, userID, 365)
    if len(dates) == 0 {
        return 0
    }

    now := time.Now().UTC()
    today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

    streak := 0
    checkDate := today

    // Check if today has a completion
    hasToday := false
    for _, date := range dates {
        if date.Equal(today) {
            hasToday = true
            break
        }
    }
    if !hasToday {
        // If no completion today, check if yesterday has one
        yesterday := today.Add(-24 * time.Hour)
        hasYesterday := false
        for _, date := range dates {
            if date.Equal(yesterday) {
                hasYesterday = true
                checkDate = yesterday
                break
            }
        }
        if !hasYesterday {
            return 0 // Streak broken
        }
    }

    // Walk backwards counting consecutive days
    for {
        found := false
        for _, date := range dates {
            if date.Equal(checkDate) {
                streak++
                checkDate = checkDate.Add(-24 * time.Hour)
                found = true
                break
            }
        }
        if !found {
            break
        }
    }

    return streak
}
```

### Progress Percentage

```go
func (s *HabitLogService) GetProgressPercentage(habitID string, userID uint, targetCount int) int {
    if targetCount <= 0 {
        return 0
    }
    todayCount := s.GetTodayProgress(habitID, userID)
    percentage := (todayCount * 100) / targetCount
    if percentage > 100 {
        return 100
    }
    return percentage
}
```

## API Handler Design

### Habit Handler

```go
type HabitHandler struct {
    service *HabitService
}

// Request/Response DTOs
type CreateHabitRequest struct {
    HabitID      string  `json:"habit_id" binding:"required"`
    Title        string  `json:"title" binding:"required"`
    TargetCount  int     `json:"target_count"`
    Unit         string  `json:"unit"`
    TriggerType  string  `json:"trigger_type" binding:"required"`
    // ... full set of fields
}

type UpdateHabitRequest struct {
    Title        *string `json:"title"`
    TargetCount  *int    `json:"target_count"`
    // ... full set of optional fields
}

type ListHabitsRequest struct {
    Page      int    `form:"page,default=1"`
    PageSize  int    `form:"page_size,default=20"`
    IsEnabled *bool  `form:"is_enabled"`
}

// HTTP Handlers
func (h *HabitHandler) Create(c *gin.Context)
func (h *HabitHandler) GetByID(c *gin.Context)
func (h *HabitHandler) GetByHabitID(c *gin.Context)
func (h *HabitHandler) List(c *gin.Context)
func (h *HabitHandler) Update(c *gin.Context)
func (h *HabitHandler) Delete(c *gin.Context)
func (h *HabitHandler) ToggleEnabled(c *gin.Context)
func (h *HabitHandler) Sync(c *gin.Context)
func (h *HabitHandler) InitializeDefaults(c *gin.Context)
```

### HabitLog Handler

```go
type HabitLogHandler struct {
    service *HabitLogService
}

type LogCompletionRequest struct {
    Count  int  `json:"count"`
    Status int  `json:"status"` // 0: completed, 1: skipped
}

type ListHabitLogsRequest struct {
    Page      int    `form:"page,default=1"`
    PageSize  int    `form:"page_size,default=50"`
    StartDate string `form:"start_date"`
    EndDate   string `form:"end_date"`
}

// HTTP Handlers
func (h *HabitLogHandler) LogCompletion(c *gin.Context)
func (h *HabitLogHandler) List(c *gin.Context)
func (h *HabitLogHandler) GetStats(c *gin.Context)
func (h *HabitLogHandler) GetHistory(c *gin.Context)
```

## Request/Response Examples

### Create Habit

**Request:**
```json
POST /api/v1/habits
{
  "habit_id": "habit_water",
  "title": "喝水",
  "target_count": 8,
  "unit": "杯",
  "trigger_type": "interval",
  "interval_minutes": 60,
  "schedule_type": "weekdays",
  "icon_code": 128167,
  "sound_enabled": true,
  "vibration_enabled": true,
  "voice_enabled": true,
  "voice_text": "该休息一下了，喝水",
  "voice_speed": "normal",
  "is_enabled": true,
  "sort_order": 0,
  "device_id": "device-abc-123"
}
```

**Response:**
```json
{
  "id": 1,
  "habit_id": "habit_water",
  "title": "喝水",
  "target_count": 8,
  "unit": "杯",
  "trigger_type": "interval",
  "interval_minutes": 60,
  "schedule_type": "weekdays",
  "icon_code": 128167,
  "sound_enabled": true,
  "vibration_enabled": true,
  "voice_enabled": true,
  "voice_text": "该休息一下了，喝水",
  "voice_speed": "normal",
  "is_enabled": true,
  "sort_order": 0,
  "user_id": 1,
  "created_at": "2026-03-29T05:00:00Z",
  "updated_at": "2026-03-29T05:00:00Z",
  "synced_at": "2026-03-29T05:00:00Z"
}
```

### Log Completion

**Request:**
```json
POST /api/v1/habits/habit_water/logs
{
  "count": 1,
  "status": 0,
  "device_id": "device-abc-123"
}
```

**Response:**
```json
{
  "id": 1,
  "habit_id": "habit_water",
  "count": 1,
  "status": 0,
  "completed_at": "2026-03-29T10:30:00Z",
  "user_id": 1,
  "created_at": "2026-03-29T10:30:00Z",
  "updated_at": "2026-03-29T10:30:00Z"
}
```

### Get Statistics

**Request:**
```http
GET /api/v1/habits/habit_water/stats
```

**Response:**
```json
{
  "today_progress": 3,
  "target_count": 8,
  "percentage": 37,
  "streak_days": 5,
  "last_completed": "2026-03-29T10:30:00Z"
}
```

### Get History

**Request:**
```http
GET /api/v1/habits/habit_water/history?days=30
```

**Response:**
```json
{
  "history": [
    {
      "date": "2026-03-29",
      "count": 3,
      "status": "completed"
    },
    {
      "date": "2026-03-28",
      "count": 8,
      "status": "completed"
    },
    {
      "date": "2026-03-27",
      "count": 6,
      "status": "partial"
    },
    {
      "date": "2026-03-26",
      "count": 0,
      "status": "skipped"
    }
  ]
}
```

## Sync Strategy

### Client-Initiated Sync

```
┌─────────────────────────────────────────────────────────────────┐
│                    SYNC FLOW                                     │
└─────────────────────────────────────────────────────────────────┘

Client                              Server
  │                                   │
  │  ── Pull: GET /api/v1/habits ──▶   │
  │  ◀──────────────────── Response ──  │
  │                                   │
  │  [Merge local & server data]       │
  │  [Resolve conflicts: last write wins]│
  │                                   │
  │  ── Push: POST /api/v1/habits/sync │
  │        (with merged habits) ──▶    │
  │  ◀──────────────────── Response ──  │
  │                                   │
```

### Conflict Resolution Rules

1. **Same HabitID, Different Timestamps**: Use `synced_at` for comparison, latest wins
2. **Habit Exists on Server, Not in Client**: Keep server version
3. **Habit Exists on Client, Not on Server**: Upload client version
4. **Soft Deletion**: Server marks `deleted_at`, client removes locally

## Error Handling

### Service Layer Errors

```go
var (
    ErrHabitNotFound      = errors.New("habit not found")
    ErrHabitAlreadyExists = errors.New("habit with this ID already exists")
    ErrInvalidTriggerType = errors.New("invalid trigger type")
    ErrMissingInterval    = errors.New("interval_minutes required for interval trigger")
    ErrMissingFixedTime   = errors.New("fixed_time required for fixed trigger")
    ErrUnauthorized       = errors.New("unauthorized access to habit")
    ErrInvalidTarget      = errors.New("target_count must be positive")
)
```

### HTTP Status Code Mapping

| Error | HTTP Status |
|-------|-------------|
| HabitNotFound | 404 |
| AlreadyExists | 409 |
| Unauthorized | 403 |
| InvalidInput | 400 |
| InternalError | 500 |

## Performance Considerations

1. **Pagination**: All list endpoints support pagination (default 20-50 items)
2. **Indexes**: Key indexes on `user_id`, `habit_id`, `device_id`, `(habit_id, completed_at)`
3. **Caching**: Consider caching habit stats (5-10 minute TTL)
4. **Batch Operations**: Use `CreateInBatches()` for bulk sync
5. **Query Optimization**: Use `Preload()` sparingly, join only when needed

## Testing Strategy

### Repository Tests
- Test CRUD operations with in-memory SQLite
- Test sync conflict scenarios
- Test streak calculation edge cases (month boundaries, leap years)

### Service Tests
- Test business logic (ownership, validation)
- Test statistics calculations
- Test preset habit initialization

### API Tests
- Test all endpoints with valid/invalid inputs
- Test JWT authentication requirements
- Test error responses
- Test pagination

### Integration Tests
- Test end-to-end sync flow
- Test multi-device scenario
- Test database migrations