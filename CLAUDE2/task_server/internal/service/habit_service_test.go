package service

import (
	"errors"
	"testing"
	"task_server/internal/model"
	"task_server/internal/repository"
	"task_server/testdata"
)

func newHabitServiceWithMock() (*HabitService, *testdata.MockHabitRepository) {
	mock := testdata.NewMockHabitRepository()
	svc := NewHabitService(mock)
	return svc, mock
}

// ========== Create Tests ==========

func TestHabitService_Create(t *testing.T) {
	tests := []struct {
		name    string
		setup   func(*testdata.MockHabitRepository)
		req     *model.CreateHabitRequest
		wantErr error
	}{
		{
			name:  "success with interval trigger",
			setup: func(m *testdata.MockHabitRepository) {},
			req: func() *model.CreateHabitRequest {
				interval := 60
				return &model.CreateHabitRequest{
					HabitID:         "habit_001",
					Title:           "Drink Water",
					TargetCount:     8,
					Unit:            "杯",
					TriggerType:     "interval",
					IntervalMinutes: &interval,
					ScheduleType:    "weekdays",
					IconCode:        0x1F4A7,
				}
			}(),
			wantErr: nil,
		},
		{
			name: "success with fixed trigger",
			setup: func(m *testdata.MockHabitRepository) {},
			req: &model.CreateHabitRequest{
				HabitID:      "habit_002",
				Title:        "Clock In",
				TriggerType:  "fixed",
				FixedTime:    "09:00",
				ScheduleType: "weekdays",
				IconCode:     0x1F4E5,
			},
			wantErr: nil,
		},
		{
			name: "fail - invalid trigger type",
			req: &model.CreateHabitRequest{
				HabitID:     "habit_003",
				Title:       "Bad Trigger",
				TriggerType: "invalid",
				IconCode:    1,
			},
			wantErr: ErrInvalidTriggerType,
		},
		{
			name: "fail - missing interval for interval trigger",
			req: &model.CreateHabitRequest{
				HabitID:     "habit_004",
				Title:       "No Interval",
				TriggerType: "interval",
				IconCode:    1,
			},
			wantErr: ErrMissingInterval,
		},
		{
			name: "fail - missing fixed time for fixed trigger",
			req: &model.CreateHabitRequest{
				HabitID:     "habit_005",
				Title:       "No Fixed Time",
				TriggerType: "fixed",
				IconCode:    1,
			},
			wantErr: ErrMissingFixedTime,
		},
		{
			name: "fail - negative target count",
			req: &model.CreateHabitRequest{
				HabitID:     "habit_006",
				Title:       "Negative Target",
				TriggerType: "interval",
				TargetCount: -1,
				IconCode:    1,
				IntervalMinutes: func() *int { v := 60; return &v }(),
			},
			wantErr: ErrInvalidTarget,
		},
		{
			name: "fail - invalid schedule type",
			req: &model.CreateHabitRequest{
				HabitID:      "habit_007",
				Title:        "Bad Schedule",
				TriggerType:  "interval",
				ScheduleType: "monthly",
				IconCode:     1,
				IntervalMinutes: func() *int { v := 60; return &v }(),
			},
			wantErr: ErrInvalidScheduleType,
		},
		{
			name: "fail - invalid voice speed",
			req: &model.CreateHabitRequest{
				HabitID:     "habit_008",
				Title:       "Bad Voice",
				TriggerType: "interval",
				VoiceSpeed:  "turbo",
				IconCode:    1,
				IntervalMinutes: func() *int { v := 60; return &v }(),
			},
			wantErr: ErrInvalidVoiceSpeed,
		},
		{
			name: "fail - already exists",
			setup: func(m *testdata.MockHabitRepository) {
				existing := testdata.NewTestHabit(1)
				m.Habits = append(m.Habits, existing)
			},
			req: func() *model.CreateHabitRequest {
				interval := 60
				return &model.CreateHabitRequest{
					HabitID:         "habit_test_001",
					Title:           "Duplicate",
					TriggerType:     "interval",
					IntervalMinutes: &interval,
					IconCode:        1,
				}
			}(),
			wantErr: repository.ErrHabitAlreadyExists,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, mock := newHabitServiceWithMock()
			if tt.setup != nil {
				tt.setup(mock)
			}

			habit, err := svc.Create(1, tt.req)

			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Create() error = %v, want %v", err, tt.wantErr)
				}
				return
			}

			if err != nil {
				t.Fatalf("Create() unexpected error = %v", err)
			}
			if habit.ID == 0 {
				t.Error("Create() habit.ID should not be zero")
			}
			if habit.UserID != 1 {
				t.Errorf("Create() userID = %v, want 1", habit.UserID)
			}
		})
	}
}

func TestHabitService_Create_DefaultValues(t *testing.T) {
	svc, _ := newHabitServiceWithMock()

	interval := 60
	req := &model.CreateHabitRequest{
		HabitID:         "habit_defaults",
		Title:           "Defaults Test",
		TriggerType:     "interval",
		IntervalMinutes: &interval,
		IconCode:        1,
		// TargetCount, Unit, ScheduleType, VoiceSpeed left as defaults
	}

	habit, err := svc.Create(1, req)
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	if habit.TargetCount != 1 {
		t.Errorf("Create() default TargetCount = %v, want 1", habit.TargetCount)
	}
	if habit.Unit != "次" {
		t.Errorf("Create() default Unit = %v, want '次'", habit.Unit)
	}
	if habit.ScheduleType != "weekdays" {
		t.Errorf("Create() default ScheduleType = %v, want 'weekdays'", habit.ScheduleType)
	}
	if habit.VoiceSpeed != "normal" {
		t.Errorf("Create() default VoiceSpeed = %v, want 'normal'", habit.VoiceSpeed)
	}
}

// ========== GetByID Tests ==========

func TestHabitService_GetByID(t *testing.T) {
	svc, mock := newHabitServiceWithMock()

	t.Run("found", func(t *testing.T) {
		habit := testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 })
		mock.Habits = append(mock.Habits, habit)

		found, err := svc.GetByID(1, 1)
		if err != nil {
			t.Fatalf("GetByID() error = %v", err)
		}
		if found.ID != 1 {
			t.Errorf("GetByID() ID = %v, want 1", found.ID)
		}
	})

	t.Run("not found", func(t *testing.T) {
		mock.Habits = nil
		_, err := svc.GetByID(999, 1)
		if err == nil {
			t.Fatal("GetByID() should return error for non-existent habit")
		}
	})
}

// ========== GetByHabitID Tests ==========

func TestHabitService_GetByHabitID(t *testing.T) {
	svc, mock := newHabitServiceWithMock()
	habit := testdata.NewTestHabit(1)
	mock.Habits = append(mock.Habits, habit)

	found, err := svc.GetByHabitID("habit_test_001", 1)
	if err != nil {
		t.Fatalf("GetByHabitID() error = %v", err)
	}
	if found.HabitID != "habit_test_001" {
		t.Errorf("GetByHabitID() HabitID = %v, want 'habit_test_001'", found.HabitID)
	}
}

// ========== List Tests ==========

func TestHabitService_List(t *testing.T) {
	svc, mock := newHabitServiceWithMock()

	// Create test habits for user 1
	for i := 0; i < 5; i++ {
		h := testdata.NewTestHabit(1, func(h *model.Habit) {
			h.HabitID = "habit_" + string(rune('0'+i))
			h.ID = uint(i + 1)
		})
		mock.Habits = append(mock.Habits, h)
	}
	// Create habit for user 2
	mock.Habits = append(mock.Habits, testdata.NewTestHabit(2, func(h *model.Habit) {
		h.HabitID = "habit_other"
	}))

	t.Run("all habits for user", func(t *testing.T) {
		resp, err := svc.List(1, &model.ListHabitsRequest{Page: 1, PageSize: 10})
		if err != nil {
			t.Fatalf("List() error = %v", err)
		}
		if resp.Total != 5 {
			t.Errorf("List() total = %v, want 5", resp.Total)
		}
	})

	t.Run("filter by enabled", func(t *testing.T) {
		enabled := true
		resp, _ := svc.List(1, &model.ListHabitsRequest{Page: 1, PageSize: 10, IsEnabled: &enabled})
		if resp.Total != 5 {
			t.Errorf("List() enabled filter total = %v, want 5", resp.Total)
		}
	})

	t.Run("pagination", func(t *testing.T) {
		resp, _ := svc.List(1, &model.ListHabitsRequest{Page: 1, PageSize: 2})
		if len(resp.Habits) != 2 {
			t.Errorf("List() page size = %v, want 2", len(resp.Habits))
		}
		if resp.TotalPages != 3 {
			t.Errorf("List() totalPages = %v, want 3", resp.TotalPages)
		}
	})

	t.Run("other user has no habits visible", func(t *testing.T) {
		resp, _ := svc.List(3, &model.ListHabitsRequest{Page: 1, PageSize: 10})
		if resp.Total != 0 {
			t.Errorf("List() total = %v, want 0", resp.Total)
		}
	})
}

// ========== Update Tests ==========

func TestHabitService_Update(t *testing.T) {
	tests := []struct {
		name    string
		setup   func(*testdata.MockHabitRepository)
		req     *model.UpdateHabitRequest
		wantErr error
		check   func(*model.Habit) error
	}{
		{
			name: "update title",
			setup: func(m *testdata.MockHabitRepository) {
				m.Habits = append(m.Habits, testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 }))
			},
			req: &model.UpdateHabitRequest{Title: strPtr("New Title")},
			check: func(h *model.Habit) error {
				if h.Title != "New Title" {
					return errors.New("title not updated")
				}
				return nil
			},
		},
		{
			name: "update trigger type to fixed",
			setup: func(m *testdata.MockHabitRepository) {
				h := testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 })
				m.Habits = append(m.Habits, h)
			},
			req: &model.UpdateHabitRequest{
				TriggerType: strPtr("fixed"),
				FixedTime:   strPtr("09:00"),
			},
			check: func(h *model.Habit) error {
				if h.TriggerType != "fixed" {
					return errors.New("trigger type not updated")
				}
				return nil
			},
		},
		{
			name: "update with invalid voice speed",
			setup: func(m *testdata.MockHabitRepository) {
				m.Habits = append(m.Habits, testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 }))
			},
			req:     &model.UpdateHabitRequest{VoiceSpeed: strPtr("turbo")},
			wantErr: ErrInvalidVoiceSpeed,
		},
		{
			name: "update with invalid schedule type",
			setup: func(m *testdata.MockHabitRepository) {
				m.Habits = append(m.Habits, testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 }))
			},
			req:     &model.UpdateHabitRequest{ScheduleType: strPtr("monthly")},
			wantErr: ErrInvalidScheduleType,
		},
		{
			name: "update with invalid trigger config - missing interval",
			setup: func(m *testdata.MockHabitRepository) {
				m.Habits = append(m.Habits, testdata.NewTestHabit(1, func(h *model.Habit) {
					h.ID = 1
					h.IntervalMinutes = nil
					h.TriggerType = "interval"
				}))
			},
			req:     &model.UpdateHabitRequest{Title: strPtr("Updated")},
			wantErr: ErrMissingInterval,
		},
		{
			name: "update with negative target count",
			setup: func(m *testdata.MockHabitRepository) {
				m.Habits = append(m.Habits, testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 }))
			},
			req:     &model.UpdateHabitRequest{TargetCount: intPtr(-1)},
			wantErr: ErrInvalidTarget,
		},
		{
			name: "update not found",
			setup: func(m *testdata.MockHabitRepository) {
				// No habits
			},
			req:     &model.UpdateHabitRequest{Title: strPtr("Ghost")},
			wantErr: repository.ErrHabitNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, mock := newHabitServiceWithMock()
			if tt.setup != nil {
				tt.setup(mock)
			}

			habit, err := svc.Update(1, 1, tt.req)

			if tt.wantErr != nil {
				if !errors.Is(err, tt.wantErr) {
					t.Errorf("Update() error = %v, want %v", err, tt.wantErr)
				}
				return
			}

			if err != nil {
				t.Fatalf("Update() unexpected error = %v", err)
			}
			if tt.check != nil {
				if err := tt.check(habit); err != nil {
					t.Errorf("Update() check failed: %v", err)
				}
			}
		})
	}
}

// ========== Delete Tests ==========

func TestHabitService_Delete(t *testing.T) {
	svc, mock := newHabitServiceWithMock()
	mock.Habits = append(mock.Habits, testdata.NewTestHabit(1, func(h *model.Habit) { h.ID = 1 }))

	t.Run("success", func(t *testing.T) {
		err := svc.Delete(1, 1)
		if err != nil {
			t.Fatalf("Delete() error = %v", err)
		}
	})

	t.Run("not found", func(t *testing.T) {
		mock.Habits = nil
		err := svc.Delete(999, 1)
		if err == nil {
			t.Fatal("Delete() should return error for non-existent habit")
		}
	})
}

// ========== ToggleEnabled Tests ==========

func TestHabitService_ToggleEnabled(t *testing.T) {
	svc, mock := newHabitServiceWithMock()
	h := testdata.NewTestHabit(1)
	mock.Habits = append(mock.Habits, h)

	t.Run("success", func(t *testing.T) {
		err := svc.ToggleEnabled("habit_test_001", 1)
		if err != nil {
			t.Fatalf("ToggleEnabled() error = %v", err)
		}
		if mock.Habits[0].IsEnabled {
			t.Error("ToggleEnabled() should have toggled to false")
		}
	})

	t.Run("not found", func(t *testing.T) {
		err := svc.ToggleEnabled("non_existent", 1)
		if err == nil {
			t.Fatal("ToggleEnabled() should return error for non-existent habit")
		}
	})
}

// ========== SyncFromDevice Tests ==========

func TestHabitService_SyncFromDevice(t *testing.T) {
	svc, mock := newHabitServiceWithMock()

	t.Run("success with habits", func(t *testing.T) {
		habits := []*model.Habit{
			testdata.NewTestHabit(0, func(h *model.Habit) {
				h.HabitID = "sync_001"
			}),
			testdata.NewTestHabit(0, func(h *model.Habit) {
				h.HabitID = "sync_002"
			}),
		}
		err := svc.SyncFromDevice(1, "device_abc", habits)
		if err != nil {
			t.Fatalf("SyncFromDevice() error = %v", err)
		}
		// Check userID and deviceID are set
		if habits[0].UserID != 1 {
			t.Errorf("SyncFromDevice() userID = %v, want 1", habits[0].UserID)
		}
		if habits[0].DeviceID != "device_abc" {
			t.Errorf("SyncFromDevice() deviceID = %v, want 'device_abc'", habits[0].DeviceID)
		}
	})

	t.Run("empty habits list", func(t *testing.T) {
		err := svc.SyncFromDevice(1, "device_abc", []*model.Habit{})
		if err != nil {
			t.Fatalf("SyncFromDevice() error = %v", err)
		}
	})

	t.Run("bulk upsert failure", func(t *testing.T) {
		mock.BulkUpsertFn = func(habits []*model.Habit) error {
			return errors.New("db error")
		}
		err := svc.SyncFromDevice(1, "device_abc", []*model.Habit{testdata.NewTestHabit(0)})
		if err == nil {
			t.Fatal("SyncFromDevice() should return error on db failure")
		}
	})
}

// ========== Validation Tests ==========

func TestHabitService_Validation_EdgeCases(t *testing.T) {
	t.Run("empty trigger type string defaults", func(t *testing.T) {
		svc, _ := newHabitServiceWithMock()
		// Empty trigger type should fail since it's neither interval nor fixed
		interval := 60
		_, err := svc.Create(1, &model.CreateHabitRequest{
			HabitID:         "habit_empty_trigger",
			Title:           "Empty Trigger",
			TriggerType:     "",
			IntervalMinutes: &interval,
			IconCode:        1,
		})
		if !errors.Is(err, ErrInvalidTriggerType) {
			t.Errorf("expected ErrInvalidTriggerType, got = %v", err)
		}
	})

	t.Run("valid voice speeds", func(t *testing.T) {
		svc, _ := newHabitServiceWithMock()
		speeds := []string{"slow", "normal", "fast"}
		for _, speed := range speeds {
			interval := 60
			_, err := svc.Create(1, &model.CreateHabitRequest{
				HabitID:         "habit_speed_" + speed,
				Title:           "Speed " + speed,
				TriggerType:     "interval",
				IntervalMinutes: &interval,
				VoiceSpeed:      speed,
				IconCode:        1,
			})
			if err != nil {
				t.Errorf("voice speed '%s' should be valid, got error = %v", speed, err)
			}
		}
	})

	t.Run("valid schedule types", func(t *testing.T) {
		svc, _ := newHabitServiceWithMock()
		types := []string{"weekdays", "daily", ""}
		for _, st := range types {
			interval := 60
			_, err := svc.Create(1, &model.CreateHabitRequest{
				HabitID:         "habit_sched_" + st,
				Title:           "Schedule " + st,
				TriggerType:     "interval",
				IntervalMinutes: &interval,
				ScheduleType:    st,
				IconCode:        1,
			})
			if err != nil {
				t.Errorf("schedule type '%s' should be valid, got error = %v", st, err)
			}
		}
	})
}

// Helper functions for tests - use different names to avoid conflict with preset_habits_service.go
func testStrPtr(s string) *string { return &s }
func testIntPtr(i int) *int       { return &i }
