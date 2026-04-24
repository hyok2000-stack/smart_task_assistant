package service

import (
	"errors"
	"testing"
	"time"

	"task_server/internal/model"
	"task_server/internal/repository"
	"task_server/testdata"
)

func newHabitLogServiceWithMock() (*HabitLogService, *testdata.MockHabitLogRepository, *testdata.MockHabitRepository) {
	logMock := testdata.NewMockHabitLogRepository()
	habitMock := testdata.NewMockHabitRepository()
	svc := NewHabitLogService(logMock, habitMock)
	return svc, logMock, habitMock
}

// ========== LogCompletion Tests ==========

func TestHabitLogService_LogCompletion(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(*testdata.MockHabitLogRepository, *testdata.MockHabitRepository)
		habitID   string
		count     int
		status    int
		wantErr   bool
	}{
		{
			name: "success",
			setup: func(lm *testdata.MockHabitLogRepository, hm *testdata.MockHabitRepository) {
				hm.Habits = append(hm.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
					h.HabitID = "habit_001"
				}))
			},
			habitID: "habit_001",
			count:   1,
			status:  0,
			wantErr: false,
		},
		{
			name: "habit not found",
			setup: func(lm *testdata.MockHabitLogRepository, hm *testdata.MockHabitRepository) {
				// No habits
			},
			habitID: "non_existent",
			count:   1,
			status:  0,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, logMock, habitMock := newHabitLogServiceWithMock()
			if tt.setup != nil {
				tt.setup(logMock, habitMock)
			}

			log, err := svc.LogCompletion(1, tt.habitID, tt.count, tt.status)

			if tt.wantErr {
				if err == nil {
					t.Fatal("LogCompletion() should return error")
				}
				return
			}

			if err != nil {
				t.Fatalf("LogCompletion() error = %v", err)
			}
			if log.ID == 0 {
				t.Error("LogCompletion() log.ID should not be zero")
			}
			if log.UserID != 1 {
				t.Errorf("LogCompletion() userID = %v, want 1", log.UserID)
			}
			if log.HabitID != tt.habitID {
				t.Errorf("LogCompletion() habitID = %v, want %v", log.HabitID, tt.habitID)
			}
			if log.Count != tt.count {
				t.Errorf("LogCompletion() count = %v, want %v", log.Count, tt.count)
			}
		})
	}
}

// ========== LogCompletionWithDeviceID Tests ==========

func TestHabitLogService_LogCompletionWithDeviceID(t *testing.T) {
	svc, _, habitMock := newHabitLogServiceWithMock()
	habitMock.Habits = append(habitMock.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
		h.HabitID = "habit_001"
	}))

	log, err := svc.LogCompletionWithDeviceID(1, "habit_001", 2, 0, "device_abc")
	if err != nil {
		t.Fatalf("LogCompletionWithDeviceID() error = %v", err)
	}
	if log.DeviceID != "device_abc" {
		t.Errorf("LogCompletionWithDeviceID() deviceID = %v, want 'device_abc'", log.DeviceID)
	}
	if log.Count != 2 {
		t.Errorf("LogCompletionWithDeviceID() count = %v, want 2", log.Count)
	}
}

// ========== List Tests ==========

func TestHabitLogService_List(t *testing.T) {
	svc, logMock, habitMock := newHabitLogServiceWithMock()
	habitMock.Habits = append(habitMock.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
		h.HabitID = "habit_001"
	}))

	// Create logs
	for i := 0; i < 5; i++ {
		logMock.Logs = append(logMock.Logs, &model.HabitLog{
			ID:          uint(i + 1),
			UserID:      1,
			HabitID:     "habit_001",
			Count:       1,
			Status:      0,
			CompletedAt: time.Now().UTC(),
		})
	}

	t.Run("first page", func(t *testing.T) {
		resp, err := svc.List("habit_001", 1, &model.ListHabitLogsRequest{Page: 1, PageSize: 3})
		if err != nil {
			t.Fatalf("List() error = %v", err)
		}
		if resp.Total != 5 {
			t.Errorf("List() total = %v, want 5", resp.Total)
		}
		if len(resp.Logs) != 3 {
			t.Errorf("List() page size = %v, want 3", len(resp.Logs))
		}
		if resp.TotalPages != 2 {
			t.Errorf("List() totalPages = %v, want 2", resp.TotalPages)
		}
	})

	t.Run("habit not found", func(t *testing.T) {
		_, err := svc.List("non_existent", 1, &model.ListHabitLogsRequest{Page: 1, PageSize: 10})
		if err == nil {
			t.Fatal("List() should return error for non-existent habit")
		}
	})
}

// ========== GetStats Tests ==========

func TestHabitLogService_GetStats(t *testing.T) {
	svc, logMock, habitMock := newHabitLogServiceWithMock()
	habit := testdata.NewTestHabit(1, func(h *model.Habit) {
		h.HabitID = "habit_001"
		h.TargetCount = 8
	})
	habitMock.Habits = append(habitMock.Habits, habit)

	t.Run("with progress", func(t *testing.T) {
		logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
			return 4, nil
		}

		stats, err := svc.GetStats("habit_001", 1)
		if err != nil {
			t.Fatalf("GetStats() error = %v", err)
		}
		if stats.TodayProgress != 4 {
			t.Errorf("GetStats() todayProgress = %v, want 4", stats.TodayProgress)
		}
		if stats.TargetCount != 8 {
			t.Errorf("GetStats() targetCount = %v, want 8", stats.TargetCount)
		}
		if stats.Percentage != 50 {
			t.Errorf("GetStats() percentage = %v, want 50", stats.Percentage)
		}
	})

	t.Run("over 100% capped", func(t *testing.T) {
		logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
			return 10, nil
		}

		stats, _ := svc.GetStats("habit_001", 1)
		if stats.Percentage != 100 {
			t.Errorf("GetStats() percentage = %v, want 100 (capped)", stats.Percentage)
		}
	})

	t.Run("habit not found", func(t *testing.T) {
		_, err := svc.GetStats("non_existent", 1)
		if err == nil {
			t.Fatal("GetStats() should return error for non-existent habit")
		}
	})
}

// ========== CalculateStreak Tests ==========

func TestHabitLogService_CalculateStreak(t *testing.T) {
	tests := []struct {
		name          string
		setupDates    func() []time.Time
		expectedStreak int
	}{
		{
			name: "no completion dates",
			setupDates: func() []time.Time {
				return nil
			},
			expectedStreak: 0,
		},
		{
			name: "only today",
			setupDates: func() []time.Time {
				now := time.Now().UTC()
				today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
				return []time.Time{today}
			},
			expectedStreak: 1,
		},
		{
			name: "3-day streak ending today",
			setupDates: func() []time.Time {
				now := time.Now().UTC()
				today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
				return []time.Time{
					today,
					today.Add(-24 * time.Hour),
					today.Add(-48 * time.Hour),
				}
			},
			expectedStreak: 3,
		},
		{
			name: "streak ending yesterday",
			setupDates: func() []time.Time {
				now := time.Now().UTC()
				today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
				yesterday := today.Add(-24 * time.Hour)
				return []time.Time{
					yesterday,
					yesterday.Add(-24 * time.Hour),
				}
			},
			expectedStreak: 2,
		},
		{
			name: "broken streak - gap of 2 days",
			setupDates: func() []time.Time {
				now := time.Now().UTC()
				today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
				return []time.Time{
					today,
					today.Add(-72 * time.Hour), // 3 days ago, gap after yesterday
				}
			},
			expectedStreak: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, logMock, _ := newHabitLogServiceWithMock()
			dates := tt.setupDates()

			logMock.GetUniqueCompletionDatesFn = func(habitID string, userID uint, days int) ([]time.Time, error) {
				return dates, nil
			}

			streak, err := svc.CalculateStreak("habit_001", 1)
			if err != nil {
				t.Fatalf("CalculateStreak() error = %v", err)
			}
			if streak != tt.expectedStreak {
				t.Errorf("CalculateStreak() = %v, want %v", streak, tt.expectedStreak)
			}
		})
	}
}

// ========== GetTodayProgress Tests ==========

func TestHabitLogService_GetTodayProgress(t *testing.T) {
	svc, logMock, _ := newHabitLogServiceWithMock()

	logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
		return 5, nil
	}

	progress, err := svc.GetTodayProgress("habit_001", 1)
	if err != nil {
		t.Fatalf("GetTodayProgress() error = %v", err)
	}
	if progress != 5 {
		t.Errorf("GetTodayProgress() = %v, want 5", progress)
	}
}

// ========== GetProgressPercentage Tests ==========

func TestHabitLogService_GetProgressPercentage(t *testing.T) {
	tests := []struct {
		name        string
		todayCount  int
		targetCount int
		wantPct     int
	}{
		{"zero target", 5, 0, 0},
		{"50 percent", 4, 8, 50},
		{"100 percent exact", 8, 8, 100},
		{"over 100 capped", 10, 8, 100},
		{"zero progress", 0, 8, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, logMock, _ := newHabitLogServiceWithMock()
			logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
				return tt.todayCount, nil
			}

			pct, err := svc.GetProgressPercentage("habit_001", 1, tt.targetCount)
			if err != nil {
				t.Fatalf("GetProgressPercentage() error = %v", err)
			}
			if pct != tt.wantPct {
				t.Errorf("GetProgressPercentage() = %v, want %v", pct, tt.wantPct)
			}
		})
	}
}

// ========== GetTodayStatsForAll Tests ==========

func TestHabitLogService_GetTodayStatsForAll(t *testing.T) {
	svc, logMock, habitMock := newHabitLogServiceWithMock()

	// Create habits for user
	for i := 0; i < 3; i++ {
		h := testdata.NewTestHabit(1, func(h *model.Habit) {
			h.HabitID = "habit_" + string(rune('0'+i))
			h.TargetCount = 8
		})
		habitMock.Habits = append(habitMock.Habits, h)
	}

	logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
		return 4, nil
	}

	stats, err := svc.GetTodayStatsForAll(1)
	if err != nil {
		t.Fatalf("GetTodayStatsForAll() error = %v", err)
	}
	if len(stats) != 3 {
		t.Errorf("GetTodayStatsForAll() count = %v, want 3", len(stats))
	}
	for habitID, stat := range stats {
		if stat.TodayProgress != 4 {
			t.Errorf("GetTodayStatsForAll() progress for %v = %v, want 4", habitID, stat.TodayProgress)
		}
		if stat.Percentage != 50 {
			t.Errorf("GetTodayStatsForAll() percentage for %v = %v, want 50", habitID, stat.Percentage)
		}
	}
}

// ========== Error Propagation Tests ==========

func TestHabitLogService_DatabaseErrors(t *testing.T) {
	t.Run("create log db error", func(t *testing.T) {
		svc, logMock, habitMock := newHabitLogServiceWithMock()
		habitMock.Habits = append(habitMock.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
			h.HabitID = "habit_001"
		}))
		logMock.CreateFn = func(log *model.HabitLog) error {
			return errors.New("db connection lost")
		}

		_, err := svc.LogCompletion(1, "habit_001", 1, 0)
		if err == nil {
			t.Fatal("LogCompletion() should propagate db error")
		}
	})

	t.Run("get stats db error on today count", func(t *testing.T) {
		svc, logMock, habitMock := newHabitLogServiceWithMock()
		habitMock.Habits = append(habitMock.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
			h.HabitID = "habit_001"
			h.TargetCount = 8
		}))
		logMock.GetTodayCountFn = func(habitID string, userID uint) (int, error) {
			return 0, errors.New("db error")
		}

		_, err := svc.GetStats("habit_001", 1)
		if err == nil {
			t.Fatal("GetStats() should propagate db error")
		}
	})

	t.Run("streak calculation returns 0 on db error", func(t *testing.T) {
		svc, logMock, _ := newHabitLogServiceWithMock()
		logMock.GetUniqueCompletionDatesFn = func(habitID string, userID uint, days int) ([]time.Time, error) {
			return nil, errors.New("db error")
		}

		streak, err := svc.CalculateStreak("habit_001", 1)
		if err != nil {
			t.Fatalf("CalculateStreak() should not return error on db error, got = %v", err)
		}
		if streak != 0 {
			t.Errorf("CalculateStreak() = %v, want 0 on db error", streak)
		}
	})
}

// Ensure repository errors are accessible
var _ = repository.ErrHabitNotFound
