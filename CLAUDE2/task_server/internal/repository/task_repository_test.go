package repository

import (
	"testing"
	"time"

	"task_server/internal/model"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func setupRepoTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dialector := sqlite.Open(":memory:")
	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(1)
	err = db.AutoMigrate(&model.User{}, &model.Task{}, &model.Tag{})
	if err != nil {
		t.Fatalf("Failed to migrate test database: %v", err)
	}
	return db
}

func seedRepoUser(db *gorm.DB) uint {
	user := &model.User{
		Username: "repo_user", Email: "repo@test.com",
		Password: "hash", IsActive: true,
	}
	db.Create(user)
	return user.ID
}

// ========== TaskRepository Tests ==========

func TestTaskRepository_Create(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	task := &model.Task{
		UserID:   userID,
		Title:    "Repo Test Task",
		Priority: 1,
		Category: "work",
		SyncedAt: time.Now(),
	}

	err := repo.Create(task)
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	if task.ID == 0 {
		t.Error("Create() task.ID should not be zero after creation")
	}
}

func TestTaskRepository_FindByID(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	t.Run("found", func(t *testing.T) {
		task := &model.Task{UserID: userID, Title: "Find Me", SyncedAt: time.Now()}
		repo.Create(task)

		found, err := repo.FindByID(task.ID)
		if err != nil {
			t.Fatalf("FindByID() error = %v", err)
		}
		if found.Title != "Find Me" {
			t.Errorf("FindByID() title = %v, want 'Find Me'", found.Title)
		}
	})

	t.Run("not found", func(t *testing.T) {
		_, err := repo.FindByID(99999)
		if err == nil {
			t.Fatal("FindByID() should return error for non-existent task")
		}
	})
}

func TestTaskRepository_FindByUserID_Filters(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	// Create tasks with various states
	completed := true
	repo.Create(&model.Task{UserID: userID, Title: "Done", Completed: completed, Priority: 1, SyncedAt: time.Now()})
	repo.Create(&model.Task{UserID: userID, Title: "High", Priority: 2, Category: "work", SyncedAt: time.Now()})
	repo.Create(&model.Task{UserID: userID, Title: "Buy groceries", Category: "personal", SyncedAt: time.Now()})
	repo.Create(&model.Task{UserID: userID, Title: "Work task", Category: "work", SyncedAt: time.Now()})

	t.Run("all tasks", func(t *testing.T) {
		tasks, total, err := repo.FindByUserID(userID, 0, 10, nil)
		if err != nil {
			t.Fatalf("FindByUserID() error = %v", err)
		}
		if total != 4 {
			t.Errorf("FindByUserID() total = %v, want 4", total)
		}
		if len(tasks) != 4 {
			t.Errorf("FindByUserID() count = %v, want 4", len(tasks))
		}
	})

	t.Run("filter completed", func(t *testing.T) {
		filters := map[string]interface{}{"completed": true}
		_, total, _ := repo.FindByUserID(userID, 0, 10, filters)
		if total != 1 {
			t.Errorf("FindByUserID() completed filter total = %v, want 1", total)
		}
	})

	t.Run("filter priority", func(t *testing.T) {
		filters := map[string]interface{}{"priority": 2}
		_, total, _ := repo.FindByUserID(userID, 0, 10, filters)
		if total != 1 {
			t.Errorf("FindByUserID() priority filter total = %v, want 1", total)
		}
	})

	t.Run("filter category", func(t *testing.T) {
		filters := map[string]interface{}{"category": "work"}
		_, total, _ := repo.FindByUserID(userID, 0, 10, filters)
		if total != 2 {
			t.Errorf("FindByUserID() category filter total = %v, want 2", total)
		}
	})

	t.Run("filter keyword", func(t *testing.T) {
		filters := map[string]interface{}{"keyword": "groceries"}
		_, total, _ := repo.FindByUserID(userID, 0, 10, filters)
		if total != 1 {
			t.Errorf("FindByUserID() keyword filter total = %v, want 1", total)
		}
	})

	t.Run("combined filters", func(t *testing.T) {
		filters := map[string]interface{}{
			"category": "work",
			"priority": 2,
		}
		_, total, _ := repo.FindByUserID(userID, 0, 10, filters)
		if total != 1 {
			t.Errorf("FindByUserID() combined filter total = %v, want 1", total)
		}
	})

	t.Run("pagination", func(t *testing.T) {
		tasks, total, _ := repo.FindByUserID(userID, 0, 2, nil)
		if total != 4 {
			t.Errorf("FindByUserID() total = %v, want 4", total)
		}
		if len(tasks) != 2 {
			t.Errorf("FindByUserID() page size = %v, want 2", len(tasks))
		}

		tasks2, _, _ := repo.FindByUserID(userID, 2, 2, nil)
		if len(tasks2) != 2 {
			t.Errorf("FindByUserID() second page size = %v, want 2", len(tasks2))
		}
	})

	t.Run("no results for other user", func(t *testing.T) {
		_, total, _ := repo.FindByUserID(99999, 0, 10, nil)
		if total != 0 {
			t.Errorf("FindByUserID() total = %v, want 0", total)
		}
	})
}

func TestTaskRepository_Update(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	task := &model.Task{UserID: userID, Title: "Original", Priority: 1, SyncedAt: time.Now()}
	repo.Create(task)

	task.Title = "Updated"
	task.Priority = 2
	err := repo.Update(task)
	if err != nil {
		t.Fatalf("Update() error = %v", err)
	}

	found, _ := repo.FindByID(task.ID)
	if found.Title != "Updated" {
		t.Errorf("Update() title = %v, want 'Updated'", found.Title)
	}
	if found.Priority != 2 {
		t.Errorf("Update() priority = %v, want 2", found.Priority)
	}
}

func TestTaskRepository_Delete(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	task := &model.Task{UserID: userID, Title: "To Delete", SyncedAt: time.Now()}
	repo.Create(task)

	err := repo.Delete(task.ID)
	if err != nil {
		t.Fatalf("Delete() error = %v", err)
	}

	_, err = repo.FindByID(task.ID)
	if err == nil {
		t.Error("Task should be deleted")
	}
}

func TestTaskRepository_GetStats(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	completed := true
	repo.Create(&model.Task{UserID: userID, Title: "Done", Completed: completed, SyncedAt: time.Now()})
	repo.Create(&model.Task{UserID: userID, Title: "Pending", Priority: 2, SyncedAt: time.Now()})
	repo.Create(&model.Task{UserID: userID, Title: "Normal", SyncedAt: time.Now()})

	stats, err := repo.GetStats(userID)
	if err != nil {
		t.Fatalf("GetStats() error = %v", err)
	}
	if stats.Total != 3 {
		t.Errorf("GetStats() total = %v, want 3", stats.Total)
	}
	if stats.Completed != 1 {
		t.Errorf("GetStats() completed = %v, want 1", stats.Completed)
	}
	if stats.Pending != 2 {
		t.Errorf("GetStats() pending = %v, want 2", stats.Pending)
	}
	if stats.HighPriority != 1 {
		t.Errorf("GetStats() highPriority = %v, want 1", stats.HighPriority)
	}
}

func TestTaskRepository_FindAll(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	for i := 0; i < 5; i++ {
		repo.Create(&model.Task{UserID: userID, Title: "Task", SyncedAt: time.Now()})
	}

	tasks, total, err := repo.FindAll(0, 3)
	if err != nil {
		t.Fatalf("FindAll() error = %v", err)
	}
	if total != 5 {
		t.Errorf("FindAll() total = %v, want 5", total)
	}
	if len(tasks) != 3 {
		t.Errorf("FindAll() page size = %v, want 3", len(tasks))
	}
}

func TestTaskRepository_FindByIDs(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	task1 := &model.Task{UserID: userID, Title: "Task 1", SyncedAt: time.Now()}
	task2 := &model.Task{UserID: userID, Title: "Task 2", SyncedAt: time.Now()}
	task3 := &model.Task{UserID: userID, Title: "Task 3", SyncedAt: time.Now()}
	repo.Create(task1)
	repo.Create(task2)
	repo.Create(task3)

	tasks, err := repo.FindByIDs([]uint{task1.ID, task3.ID})
	if err != nil {
		t.Fatalf("FindByIDs() error = %v", err)
	}
	if len(tasks) != 2 {
		t.Errorf("FindByIDs() count = %v, want 2", len(tasks))
	}
}

func TestTaskRepository_FindPendingReminders(t *testing.T) {
	db := setupRepoTestDB(t)
	repo := NewTaskRepository(db)
	userID := seedRepoUser(db)

	pastTime := time.Now().Add(-1 * time.Hour)
	repo.Create(&model.Task{
		UserID: userID, Title: "Remind Me",
		RemindAt: &pastTime, Reminded: false, SyncedAt: time.Now(),
	})
	repo.Create(&model.Task{
		UserID: userID, Title: "Already Reminded",
		RemindAt: &pastTime, Reminded: true, SyncedAt: time.Now(),
	})

	tasks, err := repo.FindPendingReminders()
	if err != nil {
		t.Fatalf("FindPendingReminders() error = %v", err)
	}
	if len(tasks) != 1 {
		t.Errorf("FindPendingReminders() count = %v, want 1", len(tasks))
	}
}
