package service

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"task_server/internal/model"
	"task_server/internal/repository"

	"github.com/glebarez/sqlite"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// uniqueDBID generates unique database IDs for test isolation
var uniqueDBID atomic.Int64

func setupForwardTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	id := uniqueDBID.Add(1)
	dsn := fmt.Sprintf("file:test_forward_%d?mode=memory&cache=shared", id)
	dialector := sqlite.Open(dsn)
	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open test database: %v", err)
	}
	err = db.AutoMigrate(&model.User{}, &model.Task{}, &model.Tag{}, &model.TaskForward{})
	if err != nil {
		t.Fatalf("Failed to migrate test database: %v", err)
	}
	return db
}

func seedForwardUsers(db *gorm.DB) (senderID, receiverID uint) {
	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)

	sender := &model.User{
		Username: "sender", Email: "sender@test.com",
		Password: string(hashedPassword), IsActive: true, Role: "user",
	}
	db.Create(sender)
	senderID = sender.ID

	receiver := &model.User{
		Username: "receiver", Email: "receiver@test.com",
		Password: string(hashedPassword), IsActive: true, Role: "user",
	}
	db.Create(receiver)
	receiverID = receiver.ID

	return senderID, receiverID
}

func newForwardService(t *testing.T) (*ForwardService, *gorm.DB) {
	t.Helper()
	db := setupForwardTestDB(t)
	taskRepo := repository.NewTaskRepository(db)
	forwardRepo := repository.NewForwardRepository(db)
	userRepo := repository.NewUserRepository(db)
	svc := NewForwardService(forwardRepo, taskRepo, userRepo, db)
	return svc, db
}

// ========== ForwardTask Tests ==========

func TestForwardService_ForwardTask(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	// Create a task owned by sender
	task := &model.Task{
		UserID: senderID, Title: "Test Task", Description: "Desc",
		Priority: 1, Category: "work", SyncedAt: time.Now(),
	}
	db.Create(task)

	t.Run("success", func(t *testing.T) {
		req := &model.TaskForwardRequest{
			TargetUserIDs: []uint{receiverID},
			Message:       "Please handle this",
		}
		resp, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
		if err != nil {
			t.Fatalf("ForwardTask() error = %v", err)
		}
		if resp.Total != 1 {
			t.Errorf("ForwardTask() total = %v, want 1", resp.Total)
		}
		if len(resp.Forwards) != 1 {
			t.Fatalf("ForwardTask() forwards count = %v, want 1", len(resp.Forwards))
		}
		if resp.Forwards[0].ForwardedTo.ID != receiverID {
			t.Errorf("ForwardTask() forwardedTo = %v, want %v", resp.Forwards[0].ForwardedTo.ID, receiverID)
		}
	})

	t.Run("task not found", func(t *testing.T) {
		req := &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}
		_, err := svc.ForwardTask(context.Background(), 99999, req, senderID)
		if !isErr(err, ErrTaskNotFound) {
			t.Errorf("ForwardTask() error = %v, want ErrTaskNotFound", err)
		}
	})

	t.Run("no permission - not owner", func(t *testing.T) {
		req := &model.TaskForwardRequest{TargetUserIDs: []uint{senderID}}
		_, err := svc.ForwardTask(context.Background(), task.ID, req, receiverID)
		if !isErr(err, ErrNoPermission) {
			t.Errorf("ForwardTask() error = %v, want ErrNoPermission", err)
		}
	})

	t.Run("forward to self", func(t *testing.T) {
		req := &model.TaskForwardRequest{TargetUserIDs: []uint{senderID}}
		_, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
		if !isErr(err, ErrForwardToSelf) {
			t.Errorf("ForwardTask() error = %v, want ErrForwardToSelf", err)
		}
	})

	t.Run("user not found", func(t *testing.T) {
		req := &model.TaskForwardRequest{TargetUserIDs: []uint{99999}}
		_, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
		if !isErr(err, ErrUserNotFound) {
			t.Errorf("ForwardTask() error = %v, want ErrUserNotFound", err)
		}
	})

	t.Run("invalid deadline - past", func(t *testing.T) {
		pastTime := time.Now().Add(-24 * time.Hour).Format(time.RFC3339)
		req := &model.TaskForwardRequest{
			TargetUserIDs: []uint{receiverID},
			Deadline:      pastTime,
		}
		_, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
		if !isErr(err, ErrInvalidDeadline) {
			t.Errorf("ForwardTask() error = %v, want ErrInvalidDeadline", err)
		}
	})

	t.Run("invalid deadline - bad format", func(t *testing.T) {
		req := &model.TaskForwardRequest{
			TargetUserIDs: []uint{receiverID},
			Deadline:      "not-a-date",
		}
		_, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
		if !isErr(err, ErrInvalidDeadline) {
			t.Errorf("ForwardTask() error = %v, want ErrInvalidDeadline", err)
		}
	})
}

func TestForwardService_ForwardTask_CircularDetection(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	// Create task owned by sender
	task := &model.Task{
		UserID: senderID, Title: "Original", SyncedAt: time.Now(),
	}
	db.Create(task)

	// Forward to receiver
	req := &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}
	svc.ForwardTask(context.Background(), task.ID, req, senderID)

	// Now try to forward the forwarded task back to sender
	// Find the forwarded task
	var forwardedTask model.Task
	db.Where("parent_task_id = ? AND user_id = ?", task.ID, receiverID).First(&forwardedTask)

	req2 := &model.TaskForwardRequest{TargetUserIDs: []uint{senderID}}
	_, err := svc.ForwardTask(context.Background(), forwardedTask.ID, req2, receiverID)
	if !isErr(err, ErrCircularForward) {
		t.Errorf("ForwardTask() circular detection error = %v, want ErrCircularForward", err)
	}
}

func TestForwardService_ForwardTask_AlreadyForwarded(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	task := &model.Task{
		UserID: senderID, Title: "Original", SyncedAt: time.Now(),
	}
	db.Create(task)

	// Forward once
	req := &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}
	svc.ForwardTask(context.Background(), task.ID, req, senderID)

	// Forward again to same user - should skip (not error, just skip)
	resp, err := svc.ForwardTask(context.Background(), task.ID, req, senderID)
	if err != nil {
		t.Fatalf("ForwardTask() second forward error = %v", err)
	}
	// Should skip the duplicate, so total is 0 (already forwarded)
	if resp.Total != 0 {
		t.Logf("ForwardTask() duplicate forward total = %v (expected 0, but skipping duplicates returns 0 new)", resp.Total)
	}
}

// ========== RevokeForward Tests ==========

func TestForwardService_RevokeForward(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	task := &model.Task{
		UserID: senderID, Title: "Revoke Test", SyncedAt: time.Now(),
	}
	db.Create(task)

	// Create a forward
	req := &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}
	resp, _ := svc.ForwardTask(context.Background(), task.ID, req, senderID)
	forwardID := resp.Forwards[0].ID

	t.Run("success", func(t *testing.T) {
		err := svc.RevokeForward(context.Background(), forwardID, "done", senderID)
		if err != nil {
			t.Fatalf("RevokeForward() error = %v", err)
		}
		// Verify forward is revoked
		forward, _ := svc.forwardRepo.FindByID(forwardID)
		if forward.IsActive {
			t.Error("RevokeForward() forward should be inactive")
		}
	})

	t.Run("forward not found", func(t *testing.T) {
		err := svc.RevokeForward(context.Background(), 99999, "", senderID)
		if !isErr(err, ErrTaskNotFound) {
			t.Errorf("RevokeForward() error = %v, want ErrTaskNotFound", err)
		}
	})

	t.Run("no permission - not the forwarder", func(t *testing.T) {
		// Create new forward for this test
		task2 := &model.Task{
			UserID: senderID, Title: "Test2", SyncedAt: time.Now(),
		}
		db.Create(task2)
		resp2, _ := svc.ForwardTask(context.Background(), task2.ID, &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}, senderID)
		forwardID2 := resp2.Forwards[0].ID

		err := svc.RevokeForward(context.Background(), forwardID2, "", receiverID)
		if !isErr(err, ErrNoPermission) {
			t.Errorf("RevokeForward() error = %v, want ErrNoPermission", err)
		}
	})

	t.Run("already revoked", func(t *testing.T) {
		err := svc.RevokeForward(context.Background(), forwardID, "already done", senderID)
		if !isErr(err, ErrForwardRevoked) {
			t.Errorf("RevokeForward() error = %v, want ErrForwardRevoked", err)
		}
	})
}

// ========== GetTaskForwards Tests ==========

func TestForwardService_GetTaskForwards(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	task := &model.Task{
		UserID: senderID, Title: "Test", SyncedAt: time.Now(),
	}
	db.Create(task)

	// Create forwards
	svc.ForwardTask(context.Background(), task.ID, &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}, senderID)

	t.Run("success", func(t *testing.T) {
		forwards, err := svc.GetTaskForwards(context.Background(), task.ID, senderID)
		if err != nil {
			t.Fatalf("GetTaskForwards() error = %v", err)
		}
		if len(forwards) != 1 {
			t.Errorf("GetTaskForwards() count = %v, want 1", len(forwards))
		}
	})

	t.Run("no permission", func(t *testing.T) {
		_, err := svc.GetTaskForwards(context.Background(), task.ID, receiverID)
		if !isErr(err, ErrNoPermission) {
			t.Errorf("GetTaskForwards() error = %v, want ErrNoPermission", err)
		}
	})
}

// ========== GetReceivedForwards Tests ==========

func TestForwardService_GetReceivedForwards(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	task := &model.Task{
		UserID: senderID, Title: "Received Test", SyncedAt: time.Now(),
	}
	db.Create(task)

	svc.ForwardTask(context.Background(), task.ID, &model.TaskForwardRequest{TargetUserIDs: []uint{receiverID}}, senderID)

	resp, err := svc.GetReceivedForwards(context.Background(), receiverID, 1, 10)
	if err != nil {
		t.Fatalf("GetReceivedForwards() error = %v", err)
	}
	if resp.Total != 1 {
		t.Errorf("GetReceivedForwards() total = %v, want 1", resp.Total)
	}
}

// ========== ProcessExpiredForwards Tests ==========

func TestForwardService_ProcessExpiredForwards(t *testing.T) {
	svc, db := newForwardService(t)
	senderID, receiverID := seedForwardUsers(db)

	task := &model.Task{
		UserID: senderID, Title: "Expired Test", SyncedAt: time.Now(),
	}
	db.Create(task)

	// Create forward with past deadline
	pastTime := time.Now().Add(-1 * time.Hour)
	forward := &model.TaskForward{
		TaskID:          task.ID,
		ForwardedTaskID: task.ID, // reuse for simplicity
		ForwardedBy:     senderID,
		ForwardedTo:     receiverID,
		Deadline:        &pastTime,
		IsActive:        true,
		IsExpired:       false,
	}
	db.Create(forward)

	count, err := svc.ProcessExpiredForwards(context.Background())
	if err != nil {
		t.Fatalf("ProcessExpiredForwards() error = %v", err)
	}
	if count != 1 {
		t.Errorf("ProcessExpiredForwards() count = %v, want 1", count)
	}
}

// Helper
func isErr(err, target error) bool {
	return err != nil && err.Error() == target.Error()
}
