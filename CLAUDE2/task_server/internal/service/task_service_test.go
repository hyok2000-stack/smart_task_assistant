package service

import (
	"task_server/internal/model"
	"task_server/internal/repository"
	"testing"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

func setupTaskTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dialector := sqlite.Open(":memory:")
	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(1)
	err = db.AutoMigrate(&model.User{}, &model.Task{}, &model.Tag{}, &model.TaskForward{})
	if err != nil {
		t.Fatalf("Failed to migrate test database: %v", err)
	}
	return db
}

func newTaskService(t *testing.T) (*TaskService, *gorm.DB) {
	t.Helper()
	db := setupTaskTestDB(t)
	taskRepo := repository.NewTaskRepository(db)
	svc := NewTaskService(taskRepo)
	return svc, db
}

func newTaskServiceWithDB(t *testing.T) (*TaskService, *gorm.DB) {
	t.Helper()
	db := setupTaskTestDB(t)
	taskRepo := repository.NewTaskRepository(db)
	forwardRepo := repository.NewForwardRepository(db)
	userRepo := repository.NewUserRepository(db)
	forwardSvc := NewForwardService(forwardRepo, taskRepo, userRepo, db)
	svc := NewTaskServiceWithForward(taskRepo, forwardRepo, forwardSvc)
	return svc, db
}

func seedUser(db *gorm.DB) uint {
	user := &model.User{
		Username: "testuser",
		Email:    "test@test.com",
		Password: "$2a$10$hash",
		Nickname: "Test",
		IsActive: true,
		Role:     "user",
	}
	db.Create(user)
	return user.ID
}

func seedOtherUser(db *gorm.DB) uint {
	user := &model.User{
		Username: "otheruser",
		Email:    "other@test.com",
		Password: "$2a$10$hash",
		Nickname: "Other",
		IsActive: true,
		Role:     "user",
	}
	db.Create(user)
	return user.ID
}

// ========== Create Tests ==========

func TestTaskService_Create(t *testing.T) {
	tests := []struct {
		name    string
		req     *model.TaskRequest
		wantErr bool
	}{
		{
			name:    "success with basic fields",
			req:     &model.TaskRequest{Title: "Test Task", Description: "Desc", Priority: 1, Category: "work"},
			wantErr: false,
		},
		{
			name:    "success with tags",
			req:     &model.TaskRequest{Title: "Tagged Task", Tags: []string{"urgent", "work"}},
			wantErr: false,
		},
		{
			name:    "success with priority 2",
			req:     &model.TaskRequest{Title: "High Priority", Priority: 2},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, db := newTaskService(t)
			userID := seedUser(db)

			task, err := svc.Create(userID, tt.req)

			if (err != nil) != tt.wantErr {
				t.Errorf("Create() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr {
				if task.ID == 0 {
					t.Error("Create() task.ID should not be zero")
				}
				if task.UserID != userID {
					t.Errorf("Create() userID = %v, want %v", task.UserID, userID)
				}
				if task.Completed {
					t.Error("Create() new task should not be completed")
				}
				if task.Title != tt.req.Title {
					t.Errorf("Create() title = %v, want %v", task.Title, tt.req.Title)
				}
			}
		})
	}
}

func TestTaskService_Create_WithTags(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	req := &model.TaskRequest{Title: "Tagged", Tags: []string{"urgent", "work"}}
	task, err := svc.Create(userID, req)

	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	fetched, _ := svc.taskRepo.FindByID(task.ID)
	if len(fetched.Tags) != 2 {
		t.Errorf("Create() tags count = %v, want 2", len(fetched.Tags))
	}
}

// ========== GetByID Tests ==========

func TestTaskService_GetByID(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	req := &model.TaskRequest{Title: "Test"}
	task, _ := svc.Create(userID, req)

	t.Run("success", func(t *testing.T) {
		found, err := svc.GetByID(task.ID, userID)
		if err != nil {
			t.Fatalf("GetByID() error = %v", err)
		}
		if found.ID != task.ID {
			t.Errorf("GetByID() ID = %v, want %v", found.ID, task.ID)
		}
	})

	t.Run("unauthorized - different user", func(t *testing.T) {
		otherUserID := seedOtherUser(db)
		_, err := svc.GetByID(task.ID, otherUserID)
		if err == nil || err.Error() != "unauthorized" {
			t.Errorf("GetByID() should return unauthorized, got = %v", err)
		}
	})

	t.Run("not found", func(t *testing.T) {
		_, err := svc.GetByID(99999, userID)
		if err == nil {
			t.Fatal("GetByID() should return error for non-existent task")
		}
	})
}

// ========== GetList Tests ==========

func TestTaskService_GetList(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	// Create tasks
	completed := true
	svc.Create(userID, &model.TaskRequest{Title: "Completed", Completed: &completed})
	svc.Create(userID, &model.TaskRequest{Title: "Incomplete A"})
	svc.Create(userID, &model.TaskRequest{Title: "Buy groceries"})
	svc.Create(userID, &model.TaskRequest{Title: "Clean house", Category: "home"})
	svc.Create(userID, &model.TaskRequest{Title: "Work task", Category: "work"})

	t.Run("all tasks", func(t *testing.T) {
		resp, err := svc.GetList(userID, &model.TaskListRequest{Page: 1, PageSize: 10})
		if err != nil {
			t.Fatalf("GetList() error = %v", err)
		}
		if resp.Total != 5 {
			t.Errorf("GetList() total = %v, want 5", resp.Total)
		}
	})

	t.Run("pagination", func(t *testing.T) {
		resp, _ := svc.GetList(userID, &model.TaskListRequest{Page: 1, PageSize: 2})
		if len(resp.Tasks) != 2 {
			t.Errorf("GetList() page size = %v, want 2", len(resp.Tasks))
		}
		if resp.TotalPages != 3 {
			t.Errorf("GetList() totalPages = %v, want 3", resp.TotalPages)
		}
	})

	t.Run("filter by completed", func(t *testing.T) {
		filterCompleted := true
		resp, _ := svc.GetList(userID, &model.TaskListRequest{Page: 1, PageSize: 10, Completed: &filterCompleted})
		if resp.Total != 1 {
			t.Errorf("GetList() filtered total = %v, want 1", resp.Total)
		}
	})

	t.Run("filter by keyword", func(t *testing.T) {
		resp, _ := svc.GetList(userID, &model.TaskListRequest{Page: 1, PageSize: 10, Keyword: "groceries"})
		if resp.Total != 1 {
			t.Errorf("GetList() keyword filter total = %v, want 1", resp.Total)
		}
	})

	t.Run("filter by category", func(t *testing.T) {
		resp, _ := svc.GetList(userID, &model.TaskListRequest{Page: 1, PageSize: 10, Category: "work"})
		if resp.Total != 1 {
			t.Errorf("GetList() category filter total = %v, want 1", resp.Total)
		}
	})

	t.Run("empty result", func(t *testing.T) {
		otherUserID := seedOtherUser(db)
		resp, _ := svc.GetList(otherUserID, &model.TaskListRequest{Page: 1, PageSize: 10})
		if resp.Total != 0 {
			t.Errorf("GetList() empty user total = %v, want 0", resp.Total)
		}
	})
}

// ========== Update Tests ==========

func TestTaskService_Update(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	t.Run("success", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Original"})
		updated, err := svc.Update(task.ID, userID, &model.TaskRequest{Title: "Updated", Priority: 2})
		if err != nil {
			t.Fatalf("Update() error = %v", err)
		}
		if updated.Title != "Updated" {
			t.Errorf("Update() title = %v, want 'Updated'", updated.Title)
		}
		if updated.Priority != 2 {
			t.Errorf("Update() priority = %v, want 2", updated.Priority)
		}
	})

	t.Run("mark as completed sets completed_at", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "To Complete"})
		completed := true
		updated, err := svc.Update(task.ID, userID, &model.TaskRequest{Title: "To Complete", Completed: &completed})
		if err != nil {
			t.Fatalf("Update() error = %v", err)
		}
		if !updated.Completed {
			t.Error("Update() task should be completed")
		}
		if updated.CompletedAt == nil {
			t.Error("Update() completed_at should be set")
		}
	})

	t.Run("unauthorized", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Owned"})
		otherUserID := seedOtherUser(db)
		_, err := svc.Update(task.ID, otherUserID, &model.TaskRequest{Title: "Hacked"})
		if err == nil || err.Error() != "unauthorized" {
			t.Errorf("Update() should return unauthorized, got = %v", err)
		}
	})

	t.Run("not found", func(t *testing.T) {
		_, err := svc.Update(99999, userID, &model.TaskRequest{Title: "Ghost"})
		if err == nil {
			t.Fatal("Update() should return error for non-existent task")
		}
	})
}

// ========== Delete Tests ==========

func TestTaskService_Delete(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	t.Run("success", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "To Delete"})
		err := svc.Delete(task.ID, userID)
		if err != nil {
			t.Fatalf("Delete() error = %v", err)
		}
		_, err = svc.GetByID(task.ID, userID)
		if err == nil {
			t.Error("Task should be deleted")
		}
	})

	t.Run("unauthorized", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Owned"})
		otherUserID := seedOtherUser(db)
		err := svc.Delete(task.ID, otherUserID)
		if err == nil || err.Error() != "unauthorized" {
			t.Errorf("Delete() should return unauthorized, got = %v", err)
		}
	})
}

// ========== ToggleComplete Tests ==========

func TestTaskService_ToggleComplete(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	t.Run("toggle to completed", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Toggle Me"})
		toggled, err := svc.ToggleComplete(task.ID, userID)
		if err != nil {
			t.Fatalf("ToggleComplete() error = %v", err)
		}
		if !toggled.Completed {
			t.Error("Task should be completed")
		}
		if toggled.CompletedAt == nil {
			t.Error("CompletedAt should be set")
		}
	})

	t.Run("toggle back to incomplete", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Toggle Back"})
		svc.ToggleComplete(task.ID, userID) // complete
		toggled, err := svc.ToggleComplete(task.ID, userID) // uncomplete
		if err != nil {
			t.Fatalf("ToggleComplete() error = %v", err)
		}
		if toggled.Completed {
			t.Error("Task should be incomplete after second toggle")
		}
		if toggled.CompletedAt != nil {
			t.Error("CompletedAt should be nil after uncompleting")
		}
	})

	t.Run("unauthorized", func(t *testing.T) {
		task, _ := svc.Create(userID, &model.TaskRequest{Title: "Owned"})
		otherUserID := seedOtherUser(db)
		_, err := svc.ToggleComplete(task.ID, otherUserID)
		if err == nil || err.Error() != "unauthorized" {
			t.Errorf("ToggleComplete() should return unauthorized, got = %v", err)
		}
	})
}

// ========== GetStats Tests ==========

func TestTaskService_GetStats(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	completed := true
	svc.Create(userID, &model.TaskRequest{Title: "Done", Completed: &completed})
	svc.Create(userID, &model.TaskRequest{Title: "High", Priority: 2})
	svc.Create(userID, &model.TaskRequest{Title: "Normal"})

	stats, err := svc.GetStats(userID)
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
		t.Errorf("GetStats() high priority = %v, want 1", stats.HighPriority)
	}
}

// ========== GetAllTasks Tests ==========

func TestTaskService_GetAllTasks(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	for i := 0; i < 7; i++ {
		svc.Create(userID, &model.TaskRequest{Title: "Task"})
	}

	t.Run("first page", func(t *testing.T) {
		resp, err := svc.GetAllTasks(1, 3)
		if err != nil {
			t.Fatalf("GetAllTasks() error = %v", err)
		}
		if resp.Total != 7 {
			t.Errorf("GetAllTasks() total = %v, want 7", resp.Total)
		}
		if len(resp.Tasks) != 3 {
			t.Errorf("GetAllTasks() count = %v, want 3", len(resp.Tasks))
		}
		if resp.TotalPages != 3 {
			t.Errorf("GetAllTasks() totalPages = %v, want 3", resp.TotalPages)
		}
	})

	t.Run("last page", func(t *testing.T) {
		resp, _ := svc.GetAllTasks(3, 3)
		if len(resp.Tasks) != 1 {
			t.Errorf("GetAllTasks() last page count = %v, want 1", len(resp.Tasks))
		}
	})
}

// ========== GetAllStats Tests ==========

func TestTaskService_GetAllStats(t *testing.T) {
	svc, db := newTaskService(t)
	userID := seedUser(db)

	completed := true
	svc.Create(userID, &model.TaskRequest{Title: "Done", Completed: &completed})
	svc.Create(userID, &model.TaskRequest{Title: "Pending"})

	stats, err := svc.GetAllStats()
	if err != nil {
		t.Fatalf("GetAllStats() error = %v", err)
	}
	if stats.Total != 2 {
		t.Errorf("GetAllStats() total = %v, want 2", stats.Total)
	}
	if stats.Completed != 1 {
		t.Errorf("GetAllStats() completed = %v, want 1", stats.Completed)
	}
}
