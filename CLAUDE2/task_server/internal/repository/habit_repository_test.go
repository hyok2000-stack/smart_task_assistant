package repository

import (
	"testing"
	"time"

	"task_server/internal/model"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func setupHabitTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dialector := sqlite.Open(":memory:")
	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(1)
	err = db.AutoMigrate(&model.User{}, &model.Habit{})
	if err != nil {
		t.Fatalf("Failed to migrate test database: %v", err)
	}
	return db
}

func seedHabitUser(db *gorm.DB) uint {
	user := &model.User{
		Username: "habit_user", Email: "habit@test.com",
		Password: "hash", IsActive: true,
	}
	db.Create(user)
	return user.ID
}

func newIntervalHabit(userID uint, habitID string) *model.Habit {
	interval := 60
	return &model.Habit{
		UserID:           userID,
		HabitID:          habitID,
		Title:            "Test Habit " + habitID,
		TriggerType:      "interval",
		IntervalMinutes:  &interval,
		ScheduleType:     "weekdays",
		VoiceSpeed:       "normal",
		IsEnabled:        true,
		TargetCount:      8,
		Unit:             "次",
		SyncedAt:         time.Now().UTC(),
	}
}

// testHabitRepo wraps a *gorm.DB to implement HabitRepository for testing
type testHabitRepo struct {
	db *gorm.DB
}

var _ HabitRepository = (*testHabitRepo)(nil)

func (r *testHabitRepo) Create(habit *model.Habit) error {
	return r.db.Create(habit).Error
}

func (r *testHabitRepo) FindByID(id uint, userID uint) (*model.Habit, error) {
	var habit model.Habit
	err := r.db.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error
	if err != nil {
		return nil, ErrHabitNotFound
	}
	return &habit, nil
}

func (r *testHabitRepo) FindByHabitID(habitID string, userID uint) (*model.Habit, error) {
	var habit model.Habit
	err := r.db.Where("habit_id = ? AND user_id = ?", habitID, userID).First(&habit).Error
	if err != nil {
		return nil, ErrHabitNotFound
	}
	return &habit, nil
}

func (r *testHabitRepo) FindByUserID(userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("user_id = ?", userID).Order("sort_order ASC").Find(&habits).Error
	return habits, err
}

func (r *testHabitRepo) Update(habit *model.Habit) error {
	return r.db.Save(habit).Error
}

func (r *testHabitRepo) Delete(id uint, userID uint) error {
	result := r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Habit{})
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return result.Error
}

func (r *testHabitRepo) DeleteByHabitID(habitID string, userID uint) error {
	result := r.db.Where("habit_id = ? AND user_id = ?", habitID, userID).Delete(&model.Habit{})
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return result.Error
}

func (r *testHabitRepo) ToggleEnabled(habitID string, userID uint) error {
	result := r.db.Model(&model.Habit{}).
		Where("habit_id = ? AND user_id = ?", habitID, userID).
		Update("is_enabled", gorm.Expr("NOT is_enabled"))
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return result.Error
}

func (r *testHabitRepo) CountByUserID(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *testHabitRepo) FindEnabledByUserID(userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("user_id = ? AND is_enabled = ?", userID, true).
		Order("sort_order ASC").Find(&habits).Error
	return habits, err
}

func (r *testHabitRepo) UpsertByDeviceID(habit *model.Habit) error {
	var existing model.Habit
	err := r.db.Where("habit_id = ? AND user_id = ?", habit.HabitID, habit.UserID).First(&existing).Error
	if err == nil {
		if habit.SyncedAt.After(existing.SyncedAt) {
			habit.ID = existing.ID
			return r.db.Save(habit).Error
		}
		return nil
	}
	return r.db.Create(habit).Error
}

func (r *testHabitRepo) FindByDeviceID(deviceID string, userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("device_id = ? AND user_id = ?", deviceID, userID).Find(&habits).Error
	return habits, err
}

func (r *testHabitRepo) BulkUpsert(habits []*model.Habit) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		for _, habit := range habits {
			var existing model.Habit
			err := tx.Where("habit_id = ? AND user_id = ?", habit.HabitID, habit.UserID).First(&existing).Error
			if err == nil {
				if habit.SyncedAt.After(existing.SyncedAt) {
					habit.ID = existing.ID
					if err := tx.Save(habit).Error; err != nil {
						return err
					}
				}
			} else if err == gorm.ErrRecordNotFound {
				if err := tx.Create(habit).Error; err != nil {
					return err
				}
			} else {
				return err
			}
		}
		return nil
	})
}

// ========== Tests ==========

func newTestHabitRepo(t *testing.T) (HabitRepository, *gorm.DB) {
	t.Helper()
	db := setupHabitTestDB(t)
	repo := &testHabitRepo{db: db}
	return repo, db
}

func TestHabitRepo_Create(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	habit := newIntervalHabit(userID, "habit_create_001")
	err := repo.Create(habit)
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	if habit.ID == 0 {
		t.Error("Create() habit.ID should not be zero")
	}
}

func TestHabitRepo_FindByID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	habit := newIntervalHabit(userID, "habit_find_001")
	repo.Create(habit)

	t.Run("found", func(t *testing.T) {
		found, err := repo.FindByID(habit.ID, userID)
		if err != nil {
			t.Fatalf("FindByID() error = %v", err)
		}
		if found.HabitID != "habit_find_001" {
			t.Errorf("FindByID() HabitID = %v, want 'habit_find_001'", found.HabitID)
		}
	})

	t.Run("wrong user returns not found", func(t *testing.T) {
		_, err := repo.FindByID(habit.ID, 99999)
		if err != ErrHabitNotFound {
			t.Errorf("FindByID() error = %v, want ErrHabitNotFound", err)
		}
	})

	t.Run("non-existent returns not found", func(t *testing.T) {
		_, err := repo.FindByID(99999, userID)
		if err != ErrHabitNotFound {
			t.Errorf("FindByID() error = %v, want ErrHabitNotFound", err)
		}
	})
}

func TestHabitRepo_FindByHabitID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	habit := newIntervalHabit(userID, "habit_habitid_001")
	repo.Create(habit)

	found, err := repo.FindByHabitID("habit_habitid_001", userID)
	if err != nil {
		t.Fatalf("FindByHabitID() error = %v", err)
	}
	if found.ID != habit.ID {
		t.Errorf("FindByHabitID() ID = %v, want %v", found.ID, habit.ID)
	}
}

func TestHabitRepo_FindByUserID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)
	otherUserID := seedHabitUser(db)

	for i := 0; i < 3; i++ {
		repo.Create(newIntervalHabit(userID, "habit_user_"+string(rune('0'+i))))
	}
	repo.Create(newIntervalHabit(otherUserID, "habit_other_001"))

	t.Run("only user habits", func(t *testing.T) {
		habits, err := repo.FindByUserID(userID)
		if err != nil {
			t.Fatalf("FindByUserID() error = %v", err)
		}
		if len(habits) != 3 {
			t.Errorf("FindByUserID() count = %v, want 3", len(habits))
		}
	})

	t.Run("other user has one habit", func(t *testing.T) {
		habits, _ := repo.FindByUserID(otherUserID)
		if len(habits) != 1 {
			t.Errorf("FindByUserID() count = %v, want 1", len(habits))
		}
	})
}

func TestHabitRepo_Update(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	habit := newIntervalHabit(userID, "habit_update_001")
	repo.Create(habit)

	habit.Title = "Updated Title"
	err := repo.Update(habit)
	if err != nil {
		t.Fatalf("Update() error = %v", err)
	}

	found, _ := repo.FindByID(habit.ID, userID)
	if found.Title != "Updated Title" {
		t.Errorf("Update() title = %v, want 'Updated Title'", found.Title)
	}
}

func TestHabitRepo_Delete(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	t.Run("success", func(t *testing.T) {
		habit := newIntervalHabit(userID, "habit_delete_001")
		repo.Create(habit)
		err := repo.Delete(habit.ID, userID)
		if err != nil {
			t.Fatalf("Delete() error = %v", err)
		}
	})

	t.Run("already deleted returns not found", func(t *testing.T) {
		habit := newIntervalHabit(userID, "habit_delete_002")
		repo.Create(habit)
		repo.Delete(habit.ID, userID)
		err := repo.Delete(habit.ID, userID)
		if err != ErrHabitNotFound {
			t.Errorf("Delete() error = %v, want ErrHabitNotFound", err)
		}
	})
}

func TestHabitRepo_ToggleEnabled(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	habit := newIntervalHabit(userID, "habit_toggle_001")
	habit.IsEnabled = true
	repo.Create(habit)

	err := repo.ToggleEnabled("habit_toggle_001", userID)
	if err != nil {
		t.Fatalf("ToggleEnabled() error = %v", err)
	}

	found, _ := repo.FindByHabitID("habit_toggle_001", userID)
	if found.IsEnabled {
		t.Error("ToggleEnabled() should have toggled to false")
	}
}

func TestHabitRepo_CountByUserID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	for i := 0; i < 4; i++ {
		repo.Create(newIntervalHabit(userID, "habit_count_"+string(rune('0'+i))))
	}

	count, err := repo.CountByUserID(userID)
	if err != nil {
		t.Fatalf("CountByUserID() error = %v", err)
	}
	if count != 4 {
		t.Errorf("CountByUserID() = %v, want 4", count)
	}
}

func TestHabitRepo_FindEnabledByUserID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	h1 := newIntervalHabit(userID, "habit_enabled_001")
	h1.IsEnabled = true
	repo.Create(h1)

	h2 := newIntervalHabit(userID, "habit_enabled_002")
	h2.IsEnabled = true
	repo.Create(h2)
	// Update h2 to disabled — GORM skips bool zero-value on Create with default tag
	db.Model(&model.Habit{}).Where("habit_id = ?", "habit_enabled_002").Update("is_enabled", false)

	habits, err := repo.FindEnabledByUserID(userID)
	if err != nil {
		t.Fatalf("FindEnabledByUserID() error = %v", err)
	}
	if len(habits) != 1 {
		t.Errorf("FindEnabledByUserID() count = %v, want 1", len(habits))
	}
}

func TestHabitRepo_UpsertByDeviceID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	t.Run("insert new", func(t *testing.T) {
		habit := newIntervalHabit(userID, "habit_upsert_001")
		err := repo.UpsertByDeviceID(habit)
		if err != nil {
			t.Fatalf("UpsertByDeviceID() error = %v", err)
		}
		found, _ := repo.FindByHabitID("habit_upsert_001", userID)
		if found == nil {
			t.Fatal("UpsertByDeviceID() habit should exist")
		}
	})

	t.Run("update existing with newer synced_at", func(t *testing.T) {
		habit := newIntervalHabit(userID, "habit_upsert_001")
		habit.Title = "Updated Title"
		habit.SyncedAt = time.Now().UTC().Add(1 * time.Hour)
		err := repo.UpsertByDeviceID(habit)
		if err != nil {
			t.Fatalf("UpsertByDeviceID() error = %v", err)
		}
		found, _ := repo.FindByHabitID("habit_upsert_001", userID)
		if found.Title != "Updated Title" {
			t.Errorf("UpsertByDeviceID() title = %v, want 'Updated Title'", found.Title)
		}
	})

	t.Run("skip update with older synced_at", func(t *testing.T) {
		habit := newIntervalHabit(userID, "habit_upsert_001")
		habit.Title = "Old Title"
		habit.SyncedAt = time.Now().UTC().Add(-2 * time.Hour)
		repo.UpsertByDeviceID(habit)
		found, _ := repo.FindByHabitID("habit_upsert_001", userID)
		if found.Title == "Old Title" {
			t.Error("UpsertByDeviceID() should not update with older synced_at")
		}
	})
}

func TestHabitRepo_FindByDeviceID(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	h1 := newIntervalHabit(userID, "habit_dev_001")
	h1.DeviceID = "device_abc"
	repo.Create(h1)

	h2 := newIntervalHabit(userID, "habit_dev_002")
	h2.DeviceID = "device_xyz"
	repo.Create(h2)

	t.Run("filter by device", func(t *testing.T) {
		habits, err := repo.FindByDeviceID("device_abc", userID)
		if err != nil {
			t.Fatalf("FindByDeviceID() error = %v", err)
		}
		if len(habits) != 1 {
			t.Errorf("FindByDeviceID() count = %v, want 1", len(habits))
		}
	})

	t.Run("no matching device", func(t *testing.T) {
		habits, _ := repo.FindByDeviceID("device_nonexistent", userID)
		if len(habits) != 0 {
			t.Errorf("FindByDeviceID() count = %v, want 0", len(habits))
		}
	})
}

func TestHabitRepo_BulkUpsert(t *testing.T) {
	repo, db := newTestHabitRepo(t)
	userID := seedHabitUser(db)

	// Pre-existing habit
	existing := newIntervalHabit(userID, "habit_bulk_001")
	existing.Title = "Original"
	repo.Create(existing)

	interval := 60
	habits := []*model.Habit{
		{
			UserID: userID, HabitID: "habit_bulk_001",
			Title: "Updated", TriggerType: "interval",
			IntervalMinutes: &interval, ScheduleType: "weekdays",
			VoiceSpeed: "normal", SyncedAt: time.Now().UTC().Add(1 * time.Hour),
		},
		{
			UserID: userID, HabitID: "habit_bulk_002",
			Title: "New Habit", TriggerType: "interval",
			IntervalMinutes: &interval, ScheduleType: "weekdays",
			VoiceSpeed: "normal", SyncedAt: time.Now().UTC(),
		},
	}

	err := repo.BulkUpsert(habits)
	if err != nil {
		t.Fatalf("BulkUpsert() error = %v", err)
	}

	// Verify update
	found1, _ := repo.FindByHabitID("habit_bulk_001", userID)
	if found1.Title != "Updated" {
		t.Errorf("BulkUpsert() title = %v, want 'Updated'", found1.Title)
	}

	// Verify insert
	found2, _ := repo.FindByHabitID("habit_bulk_002", userID)
	if found2.Title != "New Habit" {
		t.Errorf("BulkUpsert() title = %v, want 'New Habit'", found2.Title)
	}
}
