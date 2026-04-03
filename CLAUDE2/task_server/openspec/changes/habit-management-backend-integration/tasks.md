# Habit Management Backend Integration - Tasks

## Phase 1: Data Layer

### 1.1 Create Habit Model
- [x] Create `internal/model/habit.go`
- [x] Define `Habit` struct with GORM tags
- [x] Define request DTOs: `CreateHabitRequest`, `UpdateHabitRequest`, `ListHabitsRequest`
- [x] Define response DTOs: `HabitResponse`, `ListHabitsResponse`
- [x] Add JSON binding tags for validation
- [x] Test JSON serialization/deserialization

### 1.2 Create HabitLog Model
- [x] Create `internal/model/habit_log.go`
- [x] Define `HabitLog` struct with GORM tags
- [x] Define request DTO: `LogCompletionRequest`, `ListHabitLogsRequest`
- [x] Define response DTOs: `HabitLogResponse`, `ListHabitLogsResponse`
- [x] Define stats DTOs: `HabitStats`, `HabitHistoryResponse`
- [x] Test JSON serialization/deserialization

### 1.3 Implement HabitRepository
- [x] Create `internal/repository/habit_repository.go`
- [x] Implement `Create(habit *Habit) error`
- [x] Implement `FindByID(id uint, userID uint) (*Habit, error)`
- [x] Implement `FindByHabitID(habitID string, userID uint) (*Habit, error)`
- [x] Implement `FindByUserID(userID uint) ([]*Habit, error)`
- [x] Implement `Update(habit *Habit) error`
- [x] Implement `Delete(id uint, userID uint) error` (soft delete)
- [x] Implement `ToggleEnabled(habitID string, userID uint) error`
- [x] Implement `UpsertByDeviceID(habit *Habit) error` (for sync)
- [x] Implement `FindByDeviceID(deviceID string, userID uint) ([]*Habit, error)`
- [x] Implement `BulkUpsert(habits []*Habit) error`
- [x] Implement `CountByUserID(userID uint) (int64, error)`
- [x] Implement `FindEnabledByUserID(userID uint) ([]*Habit, error)`
- [ ] Add unit tests for all methods

### 1.4 Implement HabitLogRepository
- [x] Create `internal/repository/habit_log_repository.go`
- [x] Implement `Create(log *HabitLog) error`
- [x] Implement `FindByID(id uint, userID uint) (*HabitLog, error)`
- [x] Implement `FindByHabitID(habitID string, userID uint, page, pageSize int) ([]*HabitLog, int64, error)`
- [x] Implement `GetTodayCount(habitID string, userID uint) (int, error)`
- [x] Implement `GetDateRangeLogs(habitID string, userID uint, start, end time.Time) ([]*HabitLog, error)`
- [x] Implement `GetDateRangeCount(habitID string, userID uint, start, end time.Time, status int) (int, error)`
- [x] Implement `GetUniqueCompletionDates(habitID string, userID uint, days int) ([]time.Time, error)`
- [x] Implement `UpsertByDeviceID(log *HabitLog) error`
- [x] Implement `FindByDeviceID(deviceID string, userID uint, page, pageSize int) ([]*HabitLog, int64, error)`
- [x] Implement `GetDailyStatsForDateRange(habitID string, userID uint, start, end time.Time) ([]map[string]interface{}, error)`
- [x] Implement `GetLastCompletedTime(habitID string, userID uint) (*time.Time, error)`
- [x] Implement `CountTotalLogs(habitID string, userID uint) (int64, error)`
- [ ] Add unit tests for all methods

## Phase 2: Service Layer

### 2.1 Implement HabitService
- [x] Create `internal/service/habit_service.go`
- [x] Implement `Create(userID uint, req *CreateHabitRequest) (*Habit, error)`
- [x] Implement `GetByID(id uint, userID uint) (*Habit, error)`
- [x] Implement `GetByHabitID(habitID string, userID uint) (*Habit, error)`
- [x] Implement `List(userID uint, req *ListHabitsRequest) (*ListHabitsResponse, error)`
- [x] Implement `Update(id uint, userID uint, req *UpdateHabitRequest) (*Habit, error)`
- [x] Implement `Delete(id uint, userID uint) error`
- [x] Implement `ToggleEnabled(habitID string, userID uint) error`
- [x] Implement `SyncFromDevice(userID uint, deviceID string, habits []*Habit) error`
- [x] Add validation logic:
  - [x] Validate trigger_type requires interval_minutes or fixed_time
  - [x] Validate target_count is positive
  - [x] Validate voice_speed is valid (slow/normal/fast)
  - [x] Validate schedule_type is valid (weekdays/daily)
- [x] Add ownership verification for all operations
- [ ] Add unit tests

### 2.2 Implement HabitLogService
- [x] Create `internal/service/habit_log_service.go`
- [x] Implement `LogCompletionWithDeviceID(userID uint, habitID string, count int, status int, deviceID string) (*HabitLog, error)`
- [x] Implement `List(habitID string, userID uint, req *ListHabitLogsRequest) (*ListHabitLogsResponse, error)`
- [x] Implement `GetStats(habitID string, userID uint) (*HabitStats, error)`
- [x] Implement `CalculateStreak(habitID string, userID uint) (int, error)`
- [x] Implement `GetHistory(habitID string, userID uint, days int) (*HabitHistoryResponse, error)`
- [x] Implement `GetTodayProgress(habitID string, userID uint) (int, error)`
- [x] Implement `GetProgressPercentage(habitID string, userID uint, target int) (int, error)`
- [x] Implement `GetTodayStatsForAll(userID uint) (map[string]*HabitStats, error)`
- [x] Add verification that habit exists and belongs to user
- [ ] Add unit tests for streak calculation (edge cases: month boundaries, leap years, gaps)

### 2.3 Create PresetHabits Service
- [x] Create `internal/service/preset_habits.go`
- [x] Define preset habit constants matching Flutter app
- [x] Implement `GetDefaultHabits() []*Habit`
- [x] Implement `InitializeDefaults(userID uint, deviceID string) error`
- [x] Add method `HasDefaultsInitialized(userID uint) (bool, error)`
- [ ] Add unit tests

## Phase 3: API Layer

### 3.1 Implement HabitHandler
- [x] Create `internal/api/handler/habit_handler.go`
- [x] Implement `Create(c *gin.Context)`
- [x] Implement `GetByID(c *gin.Context)`
- [x] Implement `GetByHabitID(c *gin.Context)`
- [x] Implement `List(c *gin.Context)`
- [x] Implement `Update(c *gin.Context)`
- [x] Implement `Delete(c *gin.Context)`
- [x] Implement `ToggleEnabled(c *gin.Context)`
- [x] Implement `Sync(c *gin.Context)`
- [x] Implement `InitializeDefaults(c *gin.Context)`
- [x] Implement `HasDefaults(c *gin.Context)`
- [x] Implement `GetTodayWithStats(c *gin.Context)`
- [x] Add error handling and proper HTTP status codes
- [x] Add JWT context extraction (use existing pattern)
- [x] Add input validation

### 3.2 Implement HabitLogHandler
- [x] Create `internal/api/handler/habit_log_handler.go`
- [x] Implement `LogCompletion(c *gin.Context)`
- [x] Implement `List(c *gin.Context)`
- [x] Implement `GetStats(c *gin.Context)`
- [x] Implement `GetHistory(c *gin.Context)`
- [x] Implement `GetProgress(c *gin.Context)`
- [x] Implement `GetTodayProgress(c *gin.Context)`
- [x] Implement `GetStreak(c *gin.Context)`
- [x] Add error handling and proper HTTP status codes
- [x] Add JWT context extraction
- [x] Add input validation

### 3.3 Register Routes
- [x] Update `internal/api/router/router.go`
- [x] Add habit group: `/api/v1/habits`
- [x] Register habit routes:
  - [x] `POST /` - Create habit
  - [x] `GET /` - List habits
  - [x] `GET /:habit_id` - Get habit by habit_id
  - [x] `PUT /:habit_id` - Update habit
  - [x] `DELETE /:habit_id` - Delete habit
  - [x] `PATCH /:habit_id/toggle` - Toggle enabled
  - [x] `POST /sync` - Sync habits
  - [x] `POST /initialize-defaults` - Initialize default habits
  - [x] `GET /today` - Get today's habits with stats
  - [x] `GET /has-defaults` - Check if defaults initialized
- [x] Add habit log routes:
  - [x] `POST /:habit_id/logs` - Log completion
  - [x] `GET /:habit_id/logs` - List logs
  - [x] `GET /:habit_id/stats` - Get stats
  - [x] `GET /:habit_id/history` - Get history
  - [x] `GET /:habit_id/progress` - Get progress
  - [x] `GET /:habit_id/streak` - Get streak
  - [x] `GET /:habit_id/today-progress` - Get today's progress
- [x] Apply JWT middleware to all protected routes
- [ ] Test routes with curl/Postman

## Phase 4: Initialization & Configuration

### 4.1 Update Main
- [x] Update `cmd/server/main.go`
- [x] Import habit models, repositories, services, handlers
- [x] Initialize HabitRepository
- [x] Initialize HabitLogRepository
- [x] Initialize HabitService
- [x] Initialize HabitLogService
- [x] Initialize PresetHabitsService
- [x] Initialize HabitHandler
- [x] Initialize HabitLogHandler
- [x] Wire up dependencies
- [x] Test startup with no existing data

### 4.2 Database Migration
- [x] Update auto-migration in `pkg/database/database.go`
- [x] Add `model.Habit{}`
- [x] Add `model.HabitLog{}`
- [x] Test migration creates tables correctly
- [x] Test migration works with both PostgreSQL and SQLite
- [ ] Verify indexes are created

## Phase 5: Testing

### 5.1 Unit Tests
- [ ] Write repository tests (mock DB or in-memory SQLite)
- [ ] Write service tests (mock repositories)
- [ ] Test edge cases:
  - [ ] Empty habit list
  - [ ] Duplicate habit_id
  - [ ] Unauthorized access
  - [ ] Invalid trigger configurations
  - [ ] Streak calculation boundaries

### 5.2 Integration Tests
- [ ] Write API endpoint tests
- [ ] Test full CRUD flow
- [ ] Test sync scenario
- [ ] Test statistics accuracy
- [ ] Test concurrent operations
- [ ] Test with real database (PostgreSQL and SQLite)

### 5.3 Manual Testing
- [ ] Test with Flutter app integration
- [ ] Test multi-device sync
- [ ] Test offline-first scenarios
- [ ] Test preset habit initialization
- [ ] Performance testing with large datasets

## Phase 6: Documentation & Cleanup

### 6.1 Update Documentation
- [ ] Update `CLAUDE.md` with habit system details
- [ ] Update `README.md` with new API endpoints
- [ ] Add API documentation examples
- [ ] Document sync strategy

### 6.2 Code Review & Polish
- [ ] Review code for consistency with existing patterns
- [ ] Add comments for complex logic
- [ ] Run `go fmt ./...`
- [ ] Run `go vet ./...`
- [ ] Fix any linter warnings
- [ ] Ensure error messages are clear

## Optional Enhancements

- [ ] Add Redis caching for statistics
- [ ] Add habit templates/library
- [ ] Add export/import functionality
- [ ] Add habit achievement badges
- [ ] Add historical analytics dashboard
- [ ] Add habit recommendations based on patterns