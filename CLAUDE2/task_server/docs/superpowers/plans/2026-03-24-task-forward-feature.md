# Task Forward Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a task forwarding feature that allows users to forward tasks to other users with bidirectional state synchronization and expiration management.

**Architecture:** Three-tier architecture (Handler -> Service -> Repository) with explicit state synchronization in Service layer (no GORM hooks), soft delete for revoked forwards, and last-write-wins conflict resolution based on timestamps.

**Tech Stack:** Go 1.21+, Gin Web Framework, GORM ORM, PostgreSQL database, JWT authentication.

---

## File Structure

```
task_server/
├── internal/
│   ├── model/
│   │   ├── task.go                      [MODIFY] Add forward fields
│   │   └── other.go                     [MODIFY] Add TaskForward model
│   ├── repository/
│   │   ├── forward_repository.go        [CREATE] Forward data access
│   │   └── task_repository.go           [MODIFY] Add forward support methods
│   ├── service/
│   │   ├── forward_service.go           [CREATE] Forward business logic & sync
│   │   └── task_service.go              [MODIFY] Integrate with forward sync
│   ├── api/handler/
│   │   ├── forward_handler.go           [CREATE] Forward API handlers
│   │   └── user_handler.go              [MODIFY] Add SearchUsers method
│   └── api/router/
│       └── router.go                    [MODIFY] Add forward routes
├── pkg/
│   └── database/
│       └── database.go                  [MODIFY] Add migrations
└── tests/
    ├── repository/
    │   └── forward_repository_test.go   [CREATE]
    └── service/
        └── forward_service_test.go      [CREATE]
```

---

## Task 1: Add Forward Fields to Task Model

**Files:**
- Modify: `internal/model/task.go`

- [ ] **Step 1: Add forward fields to Task struct**

Open `internal/model/task.go` and add these fields after the existing `CompletedAt` field:

```go
// Forward fields
IsForwarded  bool       `gorm:"default:false" json:"is_forwarded"`
ForwardedBy  *uint      `json:"forwarded_by"`
ParentTaskID *uint      `gorm:"index" json:"parent_task_id"`
IsExpired    bool       `gorm:"default:false" json:"is_expired"`
```

- [ ] **Step 2: Run go fmt**

```bash
go fmt ./internal/model/task.go
```

Expected: No errors, file formatted

- [ ] **Step 3: Commit**

```bash
git add internal/model/task.go
git commit -m "feat: add forward fields to Task model"
```

---

## Task 2: Add TaskForward Model

**Files:**
- Modify: `internal/model/other.go`

- [ ] **Step 1: Add TaskForward model**

Open `internal/model/other.go` and add after the existing models:

```go
// TaskForward represents a task forwarding relationship
type TaskForward struct {
    ID              uint           `gorm:"primarykey" json:"id"`
    CreatedAt       time.Time      `json:"created_at"`
    UpdatedAt       time.Time      `json:"updated_at"`
    DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

    TaskID          uint           `gorm:"not null;index:idx_task_forwards_task_id" json:"task_id"`
    ForwardedTaskID uint           `gorm:"not null;index:idx_task_forwards_forwarded_task_id" json:"forwarded_task_id"`
    ForwardedBy     uint           `gorm:"not null;index:idx_task_forwards_forwarded_by" json:"forwarded_by"`
    ForwardedTo     uint           `gorm:"not null;index:idx_task_forwards_forwarded_to" json:"forwarded_to"`
    Message         string         `gorm:"type:text" json:"message"`
    Deadline        *time.Time     `json:"deadline"`
    IsExpired       bool           `gorm:"default:false" json:"is_expired"`
    IsActive        bool           `gorm:"default:true;index:idx_task_forwards_is_active" json:"is_active"`
    RevokedAt       *time.Time     `json:"revoked_at"`
    RevokedReason   string         `gorm:"type:text" json:"revoked_reason"`
}
```

- [ ] **Step 2: Add request/response models**

Add after the TaskForward model:

```go
// TaskForwardRequest is the request for forwarding a task
type TaskForwardRequest struct {
    TargetUserIDs []uint  `json:"target_user_ids" binding:"required,min=1,max=10"`
    Message       string  `json:"message" binding:"max=500"`
    Deadline      string  `json:"deadline"` // ISO 8601 format
}

// TaskForwardResponse is the response for a forward
type TaskForwardResponse struct {
    ID              uint       `json:"id"`
    ForwardedTaskID uint       `json:"forwarded_task_id"`
    TaskID          uint       `json:"task_id"`
    ForwardedBy     User       `json:"forwarded_by"`
    ForwardedTo     User       `json:"forwarded_to"`
    Message         string     `json:"message"`
    Deadline        *time.Time `json:"deadline"`
    IsExpired       bool       `json:"is_expired"`
    IsActive        bool       `json:"is_active"`
    CreatedAt       time.Time  `json:"created_at"`
}

// TaskForwardListResponse is the response for listing forwards
type TaskForwardListResponse struct {
    Forwards []TaskForwardResponse `json:"forwards"`
    Total    int                   `json:"total"`
}

// RevokeForwardRequest is the request for revoking a forward
type RevokeForwardRequest struct {
    Reason string `json:"reason" binding:"max=200"`
}

// SearchUsersRequest is the request for searching users
type SearchUsersRequest struct {
    Keyword string `form:"keyword" binding:"required,min=1"`
    Limit   int    `form:"limit,default=10"`
}

// SearchUsersResponse is the response for searching users
type SearchUsersResponse struct {
    Users []User `json:"users"`
    Total int    `json:"total"`
}

// ForwardRecordResponse is the response for forward records
type ForwardRecordResponse struct {
    ID              uint       `json:"id"`
    TaskID          uint       `json:"task_id"`
    ForwardedTaskID uint       `json:"forwarded_task_id"`
    ForwardedBy     uint       `json:"forwarded_by"`
    ForwardedTo     uint       `json:"forwarded_to"`
    Message         string     `json:"message"`
    Deadline        *time.Time `json:"deadline"`
    IsExpired       bool       `json:"is_expired"`
    IsActive        bool       `json:"is_active"`
    RevokedAt       *time.Time `json:"revoked_at"`
    CreatedAt       time.Time  `json:"created_at"`
}
```

- [ ] **Step 3: Run go fmt**

```bash
go fmt ./internal/model/other.go
```

Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add internal/model/other.go
git commit -m "feat: add TaskForward model and request/response types"
```

---

## Task 3: Create Forward Repository

**Files:**
- Create: `internal/repository/forward_repository.go`

- [ ] **Step 1: Create forward_repository.go with basic structure**

```bash
touch internal/repository/forward_repository.go
```

- [ ] **Step 2: Add imports and struct definition**

```go
package repository

import (
    "task_server/internal/model"
    "gorm.io/gorm"
)

type ForwardRepository struct {
    db *gorm.DB
}

func NewForwardRepository(db *gorm.DB) *ForwardRepository {
    return &ForwardRepository{db: db}
}
```

- [ ] **Step 3: Add Create method**

```go
// Create creates a new task forward record
func (r *ForwardRepository) Create(forward *model.TaskForward) error {
    return r.db.Create(forward).Error
}
```

- [ ] **Step 4: Add FindByID method**

```go
// FindByID finds a forward record by ID
func (r *ForwardRepository) FindByID(id uint) (*model.TaskForward, error) {
    var forward model.TaskForward
    err := r.db.Preload("Forwarder").Preload("Receiver").First(&forward, id).Error
    if err != nil {
        return nil, err
    }
    return &forward, nil
}
```

- [ ] **Step 5: Add FindByTaskID method**

```go
// FindByTaskID finds all forwards for a task
func (r *ForwardRepository) FindByTaskID(taskID uint) ([]model.TaskForward, error) {
    var forwards []model.TaskForward
    err := r.db.Preload("Forwarder").Preload("Receiver").Where("task_id = ?", taskID).Find(&forwards).Error
    return forwards, err
}
```

- [ ] **Step 6: Add FindReceivedByUserID method**

```go
// FindReceivedByUserID finds forwards received by a user
func (r *ForwardRepository) FindReceivedByUserID(userID uint, offset, limit int) ([]model.TaskForward, int64, error) {
    var forwards []model.TaskForward
    var total int64

    query := r.db.Model(&model.TaskForward{}).Where("forwarded_to = ? AND is_active = true", userID)

    err := query.Count(&total).Error
    if err != nil {
        return nil, 0, err
    }

    err = query.Preload("Forwarder").Preload("Receiver").Preload("Task").Offset(offset).Limit(limit).Order("created_at DESC").Find(&forwards).Error
    return forwards, total, err
}
```

- [ ] **Step 7: Add FindActiveForwardByTaskAndUser method**

```go
// FindActiveForwardByTaskAndUser finds an active forward for a task to a user
func (r *ForwardRepository) FindActiveForwardByTaskAndUser(taskID, toUserID uint) (*model.TaskForward, error) {
    var forward model.TaskForward
    err := r.db.Where("task_id = ? AND forwarded_to = ? AND is_active = true", taskID, toUserID).First(&forward).Error
    if err != nil {
        return nil, err
    }
    return &forward, nil
}
```

- [ ] **Step 8: Add FindActiveForwardsByTaskID method**

```go
// FindActiveForwardsByTaskID finds all active forwards for a task
func (r *ForwardRepository) FindActiveForwardsByTaskID(taskID uint) ([]model.TaskForward, error) {
    var forwards []model.TaskForward
    err := r.db.Where("task_id = ? AND is_active = true", taskID).Find(&forwards).Error
    return forwards, err
}
```

- [ ] **Step 9: Add FindForwardChain method**

```go
// FindForwardChain finds the forward chain for a task (to detect circular forwards)
func (r *ForwardRepository) FindForwardChain(taskID uint, maxDepth int) ([]uint, error) {
    chain := make([]uint, 0, maxDepth)
    currentTaskID := taskID
    visited := make(map[uint]bool)

    for i := 0; i < maxDepth; i++ {
        if visited[currentTaskID] {
            break // Cycle detected
        }
        visited[currentTaskID] = true

        var task model.Task
        err := r.db.Select("parent_task_id").First(&task, currentTaskID).Error
        if err != nil {
            break // No parent task
        }

        if task.ParentTaskID == nil {
            break // Reached the top of the chain
        }

        chain = append(chain, *task.ParentTaskID)
        currentTaskID = *task.ParentTaskID
    }

    return chain, nil
}
```

- [ ] **Step 10: Add Revoke method**

```go
// Revoke revokes a forward
func (r *ForwardRepository) Revoke(id uint, reason string, revokedAt time.Time) error {
    return r.db.Model(&model.TaskForward{}).Where("id = ?", id).Updates(map[string]interface{}{
        "is_active":      false,
        "revoked_at":     revokedAt,
        "revoked_reason": reason,
    }).Error
}
```

- [ ] **Step 11: Add CheckExpiredForwards method**

```go
// CheckExpiredForwards finds forwards that should be expired
func (r *ForwardRepository) CheckExpiredForwards() ([]model.TaskForward, error) {
    var forwards []model.TaskForward
    now := time.Now()
    err := r.db.Where("is_expired = false AND deadline < ? AND is_active = true", now).Find(&forwards).Error
    return forwards, err
}
```

- [ ] **Step 12: Add MarkAsExpired method**

```go
// MarkAsExpired marks forwards and their tasks as expired
func (r *ForwardRepository) MarkAsExpired(forwardIDs []uint) error {
    return r.db.Transaction(func(tx *gorm.DB) error {
        // Mark forwards as expired
        if err := tx.Model(&model.TaskForward{}).Where("id IN ?", forwardIDs).Update("is_expired", true).Error; err != nil {
            return err
        }

        // Get forwarded task IDs
        var forwards []model.TaskForward
        if err := tx.Where("id IN ?", forwardIDs).Find(&forwards).Error; err != nil {
            return err
        }

        taskIDs := make([]uint, 0, len(forwards))
        for _, f := range forwards {
            taskIDs = append(taskIDs, f.ForwardedTaskID)
        }

        // Mark tasks as expired (only if not completed)
        if len(taskIDs) > 0 {
            if err := tx.Model(&model.Task{}).Where("id IN ? AND completed = false", taskIDs).Update("is_expired", true).Error; err != nil {
                return err
            }
        }

        return nil
    })
}
```

- [ ] **Step 13: Run go fmt**

```bash
go fmt ./internal/repository/forward_repository.go
```

Expected: No errors

- [ ] **Step 14: Commit**

```bash
git add internal/repository/forward_repository.go
git commit -m "feat: create forward repository with CRUD and helper methods"
```

---

## Task 4: Add Forward Support Methods to Task Repository

**Files:**
- Modify: `internal/repository/task_repository.go`

- [ ] **Step 1: Add FindByIDs method**

Add after the existing methods:

```go
// FindByIDs finds tasks by multiple IDs
func (r *TaskRepository) FindByIDs(ids []uint) ([]model.Task, error) {
    var tasks []model.Task
    err := r.db.Where("id IN ?", ids).Find(&tasks).Error
    return tasks, err
}
```

- [ ] **Step 2: Run go fmt**

```bash
go fmt ./internal/repository/task_repository.go
```

- [ ] **Step 3: Commit**

```bash
git add internal/repository/task_repository.go
git commit -m "feat: add FindByIDs method to task repository"
```

---

## Task 5: Create Forward Service

**Files:**
- Create: `internal/service/forward_service.go`

- [ ] **Step 1: Create forward_service.go file**

```bash
touch internal/service/forward_service.go
```

- [ ] **Step 2: Add imports and struct definition**

```go
package service

import (
    "context"
    "errors"
    "fmt"
    "time"
    "task_server/internal/model"
    "task_server/internal/repository"

    "gorm.io/gorm"
)
```

```go
var (
    ErrTaskNotFound      = errors.New("task not found")
    ErrUserNotFound      = errors.New("user not found")
    ErrNoPermission      = errors.New("no permission")
    ErrForwardToSelf     = errors.New("cannot forward to self")
    ErrAlreadyForwarded  = errors.New("already forwarded to this user")
    ErrCircularForward   = errors.New("circular forward detected")
    ErrForwardRevoked    = errors.New("forward already revoked")
    ErrExceedLimit       = errors.New("exceed forward limit")
    ErrInvalidDeadline   = errors.New("invalid deadline")
)

type ForwardService struct {
    forwardRepo *repository.ForwardRepository
    taskRepo    *repository.TaskRepository
    userRepo    *repository.UserRepository
    db          *gorm.DB
}

func NewForwardService(
    forwardRepo *repository.ForwardRepository,
    taskRepo *repository.TaskRepository,
    userRepo *repository.UserRepository,
    db *gorm.DB,
) *ForwardService {
    return &ForwardService{
        forwardRepo: forwardRepo,
        taskRepo:    taskRepo,
        userRepo:    userRepo,
        db:          db,
    }
}
```

- [ ] **Step 3: Add ForwardTask method**

```go
// ForwardTask forwards a task to multiple users
func (s *ForwardService) ForwardTask(ctx context.Context, taskID uint, req *model.TaskForwardRequest, userID uint) (*model.TaskForwardListResponse, error) {
    // Verify task ownership
    task, err := s.taskRepo.FindByID(taskID)
    if err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, ErrTaskNotFound
        }
        return nil, err
    }

    if task.UserID != userID {
        return nil, ErrNoPermission
    }

    // Verify target users exist
    var users []model.User
    for _, targetUserID := range req.TargetUserIDs {
        if targetUserID == userID {
            return nil, ErrForwardToSelf
        }

        user, err := s.userRepo.GetByID(targetUserID)
        if err != nil {
            return nil, ErrUserNotFound
        }
        users = append(users, *user)
    }

    // Parse deadline if provided
    var deadline *time.Time
    if req.Deadline != "" {
        t, err := time.Parse(time.RFC3339, req.Deadline)
        if err != nil {
            return nil, ErrInvalidDeadline
        }
        if t.Before(time.Now()) {
            return nil, ErrInvalidDeadline
        }
        deadline = &t
    }

    // Check for circular forwards
    chain, err := s.forwardRepo.FindForwardChain(taskID, 3)
    if err != nil {
        return nil, err
    }

    userIDsInChain := make(map[uint]bool)
    for _, id := range chain {
        userIDsInChain[id] = true
    }

    for _, targetUserID := range req.TargetUserIDs {
        if userIDsInChain[targetUserID] {
            return nil, ErrCircularForward
        }
    }

    // Create forwards
    var forwardResponses []model.TaskForwardResponse

    err = s.db.Transaction(func(tx *gorm.DB) error {
        for i, targetUserID := range req.TargetUserIDs {
            // Check if already forwarded
            existing, err := s.forwardRepo.FindActiveForwardByTaskAndUser(taskID, targetUserID)
            if err == nil && existing != nil {
                // Already forwarded to this user, skip or return error
                continue // or return nil, ErrAlreadyForwarded
            }

            // Copy task for receiver
            forwardedTask := &model.Task{
                UserID:      targetUserID,
                Title:       task.Title,
                Description: task.Description,
                Completed:   task.Completed,
                Priority:    task.Priority,
                DueDate:     task.DueDate,
                RemindAt:    task.RemindAt,
                Category:    task.Category,
                IsForwarded: true,
                ForwardedBy: &userID,
                ParentTaskID: &taskID,
                IsExpired:   false,
                SyncedAt:    time.Now(),
            }

            if err := s.taskRepo.Create(forwardedTask); err != nil {
                return err
            }

            // Create forward record
            forward := &model.TaskForward{
                TaskID:          taskID,
                ForwardedTaskID: forwardedTask.ID,
                ForwardedBy:     userID,
                ForwardedTo:     targetUserID,
                Message:         req.Message,
                Deadline:        deadline,
                IsExpired:       false,
                IsActive:        true,
            }

            if err := s.forwardRepo.Create(forward); err != nil {
                return err
            }

            forwardResponses = append(forwardResponses, model.TaskForwardResponse{
                ID:              forward.ID,
                ForwardedTaskID: forward.ForwardedTaskID,
                TaskID:          forward.TaskID,
                ForwardedBy:     users[i], // Will be populated in handler
                ForwardedTo:     users[i],
                Message:         forward.Message,
                Deadline:        forward.Deadline,
                IsExpired:       forward.IsExpired,
                IsActive:        forward.IsActive,
                CreatedAt:       forward.CreatedAt,
            })
        }

        return nil
    })

    if err != nil {
        return nil, err
    }

    return &model.TaskForwardListResponse{
        Forwards: forwardResponses,
        Total:    len(forwardResponses),
    }, nil
}
```

- [ ] **Step 4: Add RevokeForward method**

```go
// RevokeForward revokes a task forward
func (s *ForwardService) RevokeForward(ctx context.Context, forwardID uint, reason string, userID uint) error {
    forward, err := s.forwardRepo.FindByID(forwardID)
    if err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return ErrTaskNotFound
        }
        return err
    }

    // Check permission
    if forward.ForwardedBy != userID {
        return ErrNoPermission
    }

    if !forward.IsActive {
        return ErrForwardRevoked
    }

    // Revoke the forward
    revokedAt := time.Now()
    if err := s.forwardRepo.Revoke(forwardID, reason, revokedAt); err != nil {
        return err
    }

    // Soft delete the forwarded task
    if err := s.db.Delete(&model.Task{}, forward.ForwardedTaskID).Error; err != nil {
        return err
    }

    return nil
}
```

- [ ] **Step 5: Add SyncTaskStatus method**

```go
// SyncTaskStatus syncs task status to all forwarded tasks
func (s *ForwardService) SyncTaskStatus(ctx context.Context, taskID uint, sourceUserID uint) error {
    return s.db.Transaction(func(tx *gorm.DB) error {
        // Find all active forwards for this task
        forwards, err := s.forwardRepo.FindActiveForwardsByTaskID(taskID)
        if err != nil {
            return err
        }

        if len(forwards) == 0 {
            return nil
        }

        // Get source task
        var sourceTask model.Task
        if err := tx.First(&sourceTask, taskID).Error; err != nil {
            return err
        }

        // Sync to each forwarded task
        for _, forward := range forwards {
            // Skip if the forward was created by the same user who is updating
            if forward.ForwardedTo == sourceUserID {
                continue
            }

            // Get target task
            var targetTask model.Task
            if err := tx.First(&targetTask, forward.ForwardedTaskID).Error; err != nil {
                continue // Task may have been deleted
            }

            // Only sync if source task is newer
            if sourceTask.UpdatedAt.After(targetTask.UpdatedAt) {
                updates := map[string]interface{}{
                    "title":       sourceTask.Title,
                    "description": sourceTask.Description,
                    "completed":   sourceTask.Completed,
                    "priority":    sourceTask.Priority,
                    "due_date":    sourceTask.DueDate,
                    "remind_at":   sourceTask.RemindAt,
                    "category":    sourceTask.Category,
                    "is_expired":  sourceTask.IsExpired,
                    "synced_at":   time.Now(),
                }

                if err := tx.Model(&model.Task{}).Where("id = ?", forward.ForwardedTaskID).Updates(updates).Error; err != nil {
                    return err
                }
            }
        }

        return nil
    })
}
```

- [ ] **Step 6: Add SyncToParentTask method**

```go
// SyncToParentTask syncs from forwarded task to parent task
func (s *ForwardService) SyncToParentTask(ctx context.Context, forwardedTaskID uint) error {
    return s.db.Transaction(func(tx *gorm.DB) error {
        // Find the forward record
        var forward model.TaskForward
        if err := tx.Where("forwarded_task_id = ? AND is_active = true", forwardedTaskID).First(&forward).Error; err != nil {
            if errors.Is(err, gorm.ErrRecordNotFound) {
                return nil // No active forward
            }
            return err
        }

        // Get source task (forwarded task)
        var sourceTask model.Task
        if err := tx.First(&sourceTask, forwardedTaskID).Error; err != nil {
            return err
        }

        // Get parent task
        var parentTask model.Task
        if err := tx.First(&parentTask, forward.TaskID).Error; err != nil {
            return err
        }

        // Only sync if forwarded task is newer
        if sourceTask.UpdatedAt.After(parentTask.UpdatedAt) {
            updates := map[string]interface{}{
                "title":       sourceTask.Title,
                "description": sourceTask.Description,
                "completed":   sourceTask.Completed,
                "priority":    sourceTask.Priority,
                "due_date":    sourceTask.DueDate,
                "remind_at":   sourceTask.RemindAt,
                "category":    sourceTask.Category,
                "synced_at":   time.Now(),
            }

            if err := tx.Model(&model.Task{}).Where("id = ?", forward.TaskID).Updates(updates).Error; err != nil {
                return err
            }
        }

        return nil
    })
}
```

- [ ] **Step 7: Add GetTaskForwards method**

```go
// GetTaskForwards gets all forwards for a task
func (s *ForwardService) GetTaskForwards(ctx context.Context, taskID uint, userID uint) ([]model.TaskForwardResponse, error) {
    // Verify task ownership
    task, err := s.taskRepo.FindByID(taskID)
    if err != nil {
        return nil, err
    }

    if task.UserID != userID {
        return nil, ErrNoPermission
    }

    forwards, err := s.forwardRepo.FindByTaskID(taskID)
    if err != nil {
        return nil, err
    }

    responses := make([]model.TaskForwardResponse, 0, len(forwards))
    for _, f := range forwards {
        responses = append(responses, model.TaskForwardResponse{
            ID:              f.ID,
            ForwardedTaskID: f.ForwardedTaskID,
            TaskID:          f.TaskID,
            ForwardedBy:     f.Forwarder,
            ForwardedTo:     f.Receiver,
            Message:         f.Message,
            Deadline:        f.Deadline,
            IsExpired:       f.IsExpired,
            IsActive:        f.IsActive,
            CreatedAt:       f.CreatedAt,
        })
    }

    return responses, nil
}
```

- [ ] **Step 8: Add GetReceivedForwards method**

```go
// GetReceivedForwards gets forwards received by a user
func (s *ForwardService) GetReceivedForwards(ctx context.Context, userID uint, page, pageSize int) (*model.TaskForwardListResponse, error) {
    offset := (page - 1) * pageSize

    forwards, total, err := s.forwardRepo.FindReceivedByUserID(userID, offset, pageSize)
    if err != nil {
        return nil, err
    }

    responses := make([]model.TaskForwardResponse, 0, len(forwards))
    for _, f := range forwards {
        responses = append(responses, model.TaskForwardResponse{
            ID:              f.ID,
            ForwardedTaskID: f.ForwardedTaskID,
            TaskID:          f.TaskID,
            ForwardedBy:     f.Forwarder,
            ForwardedTo:     f.Receiver,
            Message:         f.Message,
            Deadline:        f.Deadline,
            IsExpired:       f.IsExpired,
            IsActive:        f.IsActive,
            CreatedAt:       f.CreatedAt,
        })
    }

    return &model.TaskForwardListResponse{
        Forwards: responses,
        Total:    int(total),
    }, nil
}
```

- [ ] **Step 9: Add ProcessExpiredForwards method**

```go
// ProcessExpiredForwards marks expired forwards
func (s *ForwardService) ProcessExpiredForwards(ctx context.Context) (int, error) {
    forwards, err := s.forwardRepo.CheckExpiredForwards()
    if err != nil {
        return 0, err
    }

    if len(forwards) == 0 {
        return 0, nil
    }

    forwardIDs := make([]uint, 0, len(forwards))
    for _, f := range forwards {
        forwardIDs = append(forwardIDs, f.ID)
    }

    if err := s.forwardRepo.MarkAsExpired(forwardIDs); err != nil {
        return 0, err
    }

    return len(forwards), nil
}
```

- [ ] **Step 10: Run go fmt**

```bash
go fmt ./internal/service/forward_service.go
```

Expected: No errors

- [ ] **Step 11: Commit**

```bash
git add internal/service/forward_service.go
git commit -m "feat: create forward service with business logic and sync methods"
```

---

## Task 6: Integrate Forward Sync with Task Service

**Files:**
- Modify: `internal/service/task_service.go`

- [ ] **Step 1: Add ForwardService field to TaskService struct**

Modify the TaskService struct to include ForwardService:

```go
type TaskService struct {
    taskRepo     *repository.TaskRepository
    forwardRepo  *repository.ForwardRepository // Add this
    forwardSvc   *ForwardService               // Add this
}

func NewTaskService(taskRepo *repository.TaskRepository) *TaskService {
    return &TaskService{taskRepo: taskRepo}
}

// Add new constructor with forward support
func NewTaskServiceWithForward(taskRepo *repository.TaskRepository, forwardRepo *repository.ForwardRepository, forwardSvc *ForwardService) *TaskService {
    return &TaskService{
        taskRepo:    taskRepo,
        forwardRepo: forwardRepo,
        forwardSvc:  forwardSvc,
    }
}
```

- [ ] **Step 2: Modify Update method to sync to forwarded tasks**

Modify the Update method to add sync after update:

```go
// Update 更新任务
func (s *TaskService) Update(id uint, userID uint, req *model.TaskRequest) (*model.Task, error) {
    task, err := s.taskRepo.FindByID(id)
    if err != nil {
        return nil, err
    }

    // 检查任务是否属于该用户
    if task.UserID != userID {
        return nil, errors.New("unauthorized")
    }

    // 更新字段
    task.Title = req.Title
    task.Description = req.Description
    task.Priority = req.Priority
    task.DueDate = req.DueDate
    task.RemindAt = req.RemindAt
    task.Category = req.Category
    task.SyncedAt = time.Now()

    // 如果标记为完成，记录完成时间
    if req.Completed != nil && *req.Completed && !task.Completed {
        now := time.Now()
        task.CompletedAt = &now
    }
    task.Completed = req.Completed != nil && *req.Completed

    err = s.taskRepo.Update(task)
    if err != nil {
        return nil, err
    }

    // Sync to forwarded tasks if this is not a forwarded task
    if !task.IsForwarded && s.forwardSvc != nil {
        go s.forwardSvc.SyncTaskStatus(context.Background(), task.ID, userID)
    }

    return task, nil
}
```

- [ ] **Step 3: Modify ToggleComplete method to sync**

Modify ToggleComplete method similarly:

```go
// ToggleComplete 切换任务完成状态
func (s *TaskService) ToggleComplete(id uint, userID uint) (*model.Task, error) {
    task, err := s.taskRepo.FindByID(id)
    if err != nil {
        return nil, err
    }

    // 检查任务是否属于该用户
    if task.UserID != userID {
        return nil, errors.New("unauthorized")
    }

    task.Completed = !task.Completed
    if task.Completed {
        now := time.Now()
        task.CompletedAt = &now
    } else {
        task.CompletedAt = nil
    }
    task.SyncedAt = time.Now()

    err = s.taskRepo.Update(task)
    if err != nil {
        return nil, err
    }

    // Sync to forwarded tasks
    if !task.IsForwarded && s.forwardSvc != nil {
        go s.forwardSvc.SyncTaskStatus(context.Background(), task.ID, userID)
    } else if task.IsForwarded && s.forwardSvc != nil {
        go s.forwardSvc.SyncToParentTask(context.Background(), task.ID)
    }

    return task, nil
}
```

- [ ] **Step 4: Run go fmt**

```bash
go fmt ./internal/service/task_service.go
```

- [ ] **Step 5: Commit**

```bash
git add internal/service/task_service.go
git commit -m "feat: integrate forward sync with task service"
```

---

## Task 7: Add SearchUsers to User Repository

**Files:**
- Modify: `internal/repository/user_repository.go`

- [ ] **Step 1: Add Search method**

Read the file first, then add this method:

```go
// Search searches users by keyword (username or email)
func (r *UserRepository) Search(keyword string, limit int) ([]model.User, int64, error) {
    var users []model.User
    var total int64

    query := r.db.Model(&model.User{}).
        Where("username LIKE ? OR email LIKE ? OR nickname LIKE ?", "%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")

    err := query.Count(&total).Error
    if err != nil {
        return nil, 0, err
    }

    err = query.Limit(limit).Find(&users).Error
    return users, total, err
}
```

- [ ] **Step 2: Run go fmt**

```bash
go fmt ./internal/repository/user_repository.go
```

- [ ] **Step 3: Commit**

```bash
git add internal/repository/user_repository.go
git commit -m "feat: add Search method to user repository"
```

---

## Task 8: Add SearchUsers to User Service

**Files:**
- Modify: `internal/service/user_service.go`

- [ ] **Step 1: Add SearchUsers method**

```go
// SearchUsers searches users by keyword
func (s *UserService) SearchUsers(keyword string, limit int) (*model.SearchUsersResponse, error) {
    users, total, err := s.userRepo.Search(keyword, limit)
    if err != nil {
        return nil, err
    }

    return &model.SearchUsersResponse{
        Users: users,
        Total: int(total),
    }, nil
}
```

- [ ] **Step 2: Run go fmt**

```bash
go fmt ./internal/service/user_service.go
```

- [ ] **Step 3: Commit**

```bash
git add internal/service/user_service.go
git commit -m "feat: add SearchUsers method to user service"
```

---

## Task 9: Create Forward Handler

**Files:**
- Create: `internal/api/handler/forward_handler.go`

- [ ] **Step 1: Create forward_handler.go file**

```bash
touch internal/api/handler/forward_handler.go
```

- [ ] **Step 2: Add imports and struct definition**

```go
package handler

import (
    "net/http"
    "strconv"
    "task_server/internal/model"
    "task_server/internal/service"
    "task_server/pkg/logger"

    "github.com/gin-gonic/gin"
    "go.uber.org/zap"
)

type ForwardHandler struct {
    forwardService *service.ForwardService
    userService    *service.UserService
}

func NewForwardHandler(forwardService *service.ForwardService, userService *service.UserService) *ForwardHandler {
    return &ForwardHandler{
        forwardService: forwardService,
        userService:    userService,
    }
}
```

- [ ] **Step 3: Add ForwardTask method**

```go
// ForwardTask forwards a task
func (h *ForwardHandler) ForwardTask(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
        return
    }

    idParam := c.Param("id")
    taskID, err := strconv.ParseUint(idParam, 10, 32)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid task id"})
        return
    }

    var req model.TaskForwardRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        logger.Warn("Invalid forward request", zap.String("error", err.Error()))
        c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
        return
    }

    response, err := h.forwardService.ForwardTask(c.Request.Context(), uint(taskID), &req, userID.(uint))
    if err != nil {
        logger.Warn("Failed to forward task", zap.String("error", err.Error()))

        // Map service errors to HTTP responses
        code := 1
        message := err.Error()

        switch err {
        case service.ErrTaskNotFound:
            c.JSON(http.StatusNotFound, gin.H{"code": code, "message": "任务不存在"})
            return
        case service.ErrUserNotFound:
            c.JSON(http.StatusNotFound, gin.H{"code": code, "message": "用户不存在"})
            return
        case service.ErrNoPermission:
            c.JSON(http.StatusForbidden, gin.H{"code": code, "message": "无操作权限"})
            return
        case service.ErrForwardToSelf:
            c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "不能转发给自己"})
            return
        case service.ErrAlreadyForwarded:
            c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "该任务已转发给此用户"})
            return
        case service.ErrCircularForward:
            c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "不能产生循环转发"})
            return
        case service.ErrExceedLimit:
            c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "超过转发人数限制"})
            return
        case service.ErrInvalidDeadline:
            c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "截止时间无效"})
            return
        }

        c.JSON(http.StatusOK, gin.H{"code": code, "message": message})
        return
    }

    logger.Info("Task forwarded", zap.Uint32("task_id", uint32(taskID)), zap.Int("count", len(response.Forwards)))
    c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}
```

- [ ] **Step 4: Add RevokeForward method**

```go
// RevokeForward revokes a task forward
func (h *ForwardHandler) RevokeForward(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
        return
    }

    idParam := c.Param("id")
    forwardID, err := strconv.ParseUint(idParam, 10, 32)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid forward id"})
        return
    }

    var req model.RevokeForwardRequest
    c.ShouldBindJSON(&req) // Reason is optional

    err = h.forwardService.RevokeForward(c.Request.Context(), uint(forwardID), req.Reason, userID.(uint))
    if err != nil {
        logger.Warn("Failed to revoke forward", zap.String("error", err.Error()))

        switch err {
        case service.ErrTaskNotFound:
            c.JSON(http.StatusNotFound, gin.H{"code": 1, "message": "转发记录不存在"})
            return
        case service.ErrNoPermission:
            c.JSON(http.StatusForbidden, gin.H{"code": 1, "message": "只有转发者可以撤回"})
            return
        case service.ErrForwardRevoked:
            c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "转发已撤回"})
            return
        }

        c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
        return
    }

    logger.Info("Forward revoked", zap.Uint32("forward_id", uint32(forwardID)))
    c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success"})
}
```

- [ ] **Step 5: Add GetTaskForwards method**

```go
// GetTaskForwards gets forwards for a task
func (h *ForwardHandler) GetTaskForwards(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
        return
    }

    idParam := c.Param("id")
    taskID, err := strconv.ParseUint(idParam, 10, 32)
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid task id"})
        return
    }

    forwards, err := h.forwardService.GetTaskForwards(c.Request.Context(), uint(taskID), userID.(uint))
    if err != nil {
        logger.Error("Failed to get task forwards", zap.String("error", err.Error()))
        c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to get forwards"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": gin.H{
        "forwards": forwards,
        "total":    len(forwards),
    }})
}
```

- [ ] **Step 6: Add GetReceivedForwards method**

```go
// GetReceivedForwards gets forwards received by the user
func (h *ForwardHandler) GetReceivedForwards(c *gin.Context) {
    userID, exists := c.Get("user_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
        return
    }

    var req struct {
        Page     int `form:"page,default=1"`
        PageSize int `form:"page_size,default=10"`
    }
    if err := c.ShouldBindQuery(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
        return
    }

    response, err := h.forwardService.GetReceivedForwards(c.Request.Context(), userID.(uint), req.Page, req.PageSize)
    if err != nil {
        logger.Error("Failed to get received forwards", zap.String("error", err.Error()))
        c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to get forwards"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}
```

- [ ] **Step 7: Run go fmt**

```bash
go fmt ./internal/api/handler/forward_handler.go
```

- [ ] **Step 8: Commit**

```bash
git add internal/api/handler/forward_handler.go
git commit -m "feat: create forward handler with all API endpoints"
```

---

## Task 10: Add SearchUsers to User Handler

**Files:**
- Modify: `internal/api/handler/user_handler.go`

- [ ] **Step 1: Add SearchUsers method**

Add this method to the UserHandler:

```go
// SearchUsers searches for users by keyword
func (h *UserHandler) SearchUsers(c *gin.Context) {
    var req model.SearchUsersRequest
    if err := c.ShouldBindQuery(&req); err != nil {
        logger.Warn("Invalid search users request", zap.String("error", err.Error()))
        c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
        return
    }

    response, err := h.userService.SearchUsers(req.Keyword, req.Limit)
    if err != nil {
        logger.Error("Failed to search users", zap.String("error", err.Error()))
        c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to search users"})
        return
    }

    c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}
```

- [ ] **Step 2: Run go fmt**

```bash
go fmt ./internal/api/handler/user_handler.go
```

- [ ] **Step 3: Commit**

```bash
git add internal/api/handler/user_handler.go
git commit -m "feat: add SearchUsers endpoint to user handler"
```

---

## Task 11: Add Forward Routes

**Files:**
- Modify: `internal/api/router/router.go`

- [ ] **Step 1: Modify SetupRouter signature to accept forward handler**

```go
func SetupRouter(userHandler *handler.UserHandler, taskHandler *handler.TaskHandler, forwardHandler *handler.ForwardHandler) *gin.Engine {
```

- [ ] **Step 2: Add search users route**

Add inside the user route group:

```go
user.GET("/search", userHandler.SearchUsers)
```

- [ ] **Step 3: Add forward routes**

Add after the tasks route group:

```go
// 转发相关（需要 JWT）
tasks.POST("/:id/forward", forwardHandler.ForwardTask)
tasks.GET("/:id/forwards", forwardHandler.GetTaskForwards)

// 转发管理（需要 JWT）
forwards := v1.Group("/forwards")
forwards.Use(middleware.JWTAuth())
{
    forwards.GET("/received", forwardHandler.GetReceivedForwards)
    forwards.DELETE("/:id", forwardHandler.RevokeForward)
}
```

- [ ] **Step 4: Run go fmt**

```bash
go fmt ./internal/api/router/router.go
```

- [ ] **Step 5: Commit**

```bash
git add internal/api/router/router.go
git commit -m "feat: add forward routes to router"
```

---

## Task 12: Update Main to Initialize Forward Services

**Files:**
- Modify: `cmd/server/main.go`

- [ ] **Step 1: Add forward repository initialization**

Add after existing repository initializations:

```go
forwardRepo := repository.NewForwardRepository(db)
```

- [ ] **Step 2: Add forward service initialization**

```go
forwardService := service.NewForwardService(forwardRepo, taskRepo, userRepo, db)
```

- [ ] **Step 3: Update task service initialization**

Replace existing taskService initialization with:

```go
taskService := service.NewTaskServiceWithForward(taskRepo, forwardRepo, forwardService)
```

- [ ] **Step 4: Add forward handler initialization**

```go
forwardHandler := handler.NewForwardHandler(forwardService, userService)
```

- [ ] **Step 5: Update router initialization**

Update the SetupRouter call:

```go
router := router.SetupRouter(userHandler, taskHandler, forwardHandler)
```

- [ ] **Step 6: Run go fmt**

```bash
go fmt ./cmd/server/main.go
```

- [ ] **Step 7: Commit**

```bash
git add cmd/server/main.go
git commit -m "feat: initialize forward services and update router"
```

---

## Task 13: Add Database Migrations

**Files:**
- Modify: `pkg/database/database.go`

- [ ] **Step 1: Add TaskForward model migration**

Add in the AutoMigrate section:

```go
// Auto migrate tables
err = db.AutoMigrate(
    &model.User{},
    &model.Task{},
    &model.Tag{},
    &model.Device{},
    &model.AISuggestion{},
    &model.AIChatMessage{},
    &model.TaskForward{}, // Add this
)
```

- [ ] **Step 2: Add index creation**

Add after migrations:

```go
// Create indexes for forward functionality
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_task_id ON task_forwards(task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_task_id ON task_forwards(forwarded_task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_by ON task_forwards(forwarded_by)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_forwarded_to ON task_forwards(forwarded_to)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_task_forwards_is_active ON task_forwards(is_active)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id)")
db.Exec("CREATE INDEX IF NOT EXISTS idx_tasks_forwarded_by ON tasks(forwarded_by)")
```

- [ ] **Step 3: Run go fmt**

```bash
go fmt ./pkg/database/database.go
```

- [ ] **Step 4: Commit**

```bash
git add pkg/database/database.go
git commit -m "feat: add TaskForward migration and indexes"
```

---

## Task 14: Test Forward Repository

**Files:**
- Create: `tests/repository/forward_repository_test.go`

- [ ] **Step 1: Create test file**

```bash
mkdir -p tests/repository
touch tests/repository/forward_repository_test.go
```

- [ ] **Step 2: Write test setup and basic test**

```go
package repository_test

import (
    "testing"
    "time"
    "task_server/internal/model"

    "github.com/stretchr/testify/assert"
    "gorm.io/driver/sqlite"
    "gorm.io/gorm"
)

func setupTestDB(t *testing.T) *gorm.DB {
    db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
    assert.NoError(t, err)

    err = db.AutoMigrate(&model.User{}, &model.Task{}, &model.TaskForward{})
    assert.NoError(t, err)

    return db
}

func createTestUser(db *gorm.DB, username string) *model.User {
    user := &model.User{
        Username: username,
        Email:    username + "@test.com",
        Password: "password",
    }
    db.Create(user)
    return user
}

func createTestTask(db *gorm.DB, userID uint) *model.Task {
    task := &model.Task{
        UserID:      userID,
        Title:       "Test Task",
        Description: "Test Description",
    }
    db.Create(task)
    return task
}

func TestCreateTaskForward(t *testing.T) {
    db := setupTestDB(t)
    repo := repository.NewForwardRepository(db)

    user1 := createTestUser(db, "user1")
    user2 := createTestUser(db, "user2")
    task := createTestTask(db, user1.ID)

    forward := &model.TaskForward{
        TaskID:          task.ID,
        ForwardedTaskID: task.ID + 1,
        ForwardedBy:     user1.ID,
        ForwardedTo:     user2.ID,
        Message:         "Please help",
    }

    err := repo.Create(forward)
    assert.NoError(t, err)
    assert.NotZero(t, forward.ID)
}

func TestFindByID(t *testing.T) {
    db := setupTestDB(t)
    repo := repository.NewForwardRepository(db)

    user1 := createTestUser(db, "user1")
    user2 := createTestUser(db, "user2")
    task := createTestTask(db, user1.ID)

    forward := &model.TaskForward{
        TaskID:          task.ID,
        ForwardedTaskID: task.ID + 1,
        ForwardedBy:     user1.ID,
        ForwardedTo:     user2.ID,
    }
    repo.Create(forward)

    found, err := repo.FindByID(forward.ID)
    assert.NoError(t, err)
    assert.Equal(t, forward.ID, found.ID)
}

func TestFindActiveForwardByTaskAndUser(t *testing.T) {
    db := setupTestDB(t)
    repo := repository.NewForwardRepository(db)

    user1 := createTestUser(db, "user1")
    user2 := createTestUser(db, "user2")
    task := createTestTask(db, user1.ID)

    forward := &model.TaskForward{
        TaskID:          task.ID,
        ForwardedTaskID: task.ID + 1,
        ForwardedBy:     user1.ID,
        ForwardedTo:     user2.ID,
        IsActive:        true,
    }
    repo.Create(forward)

    found, err := repo.FindActiveForwardByTaskAndUser(task.ID, user2.ID)
    assert.NoError(t, err)
    assert.Equal(t, forward.ID, found.ID)
}
```

- [ ] **Step 3: Run tests**

```bash
go test ./tests/repository/forward_repository_test.go -v
```

Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add tests/repository/forward_repository_test.go
git commit -m "test: add forward repository tests"
```

---

## Task 15: Test Forward Service

**Files:**
- Create: `tests/service/forward_service_test.go`

- [ ] **Step 1: Create test file**

```bash
mkdir -p tests/service
touch tests/service/forward_service_test.go
```

- [ ] **Step 2: Write service tests**

```go
package service_test

import (
    "context"
    "testing"
    "time"
    "task_server/internal/model"
    "task_server/internal/repository"
    "task_server/internal/service"

    "github.com/stretchr/testify/assert"
    "gorm.io/driver/sqlite"
    "gorm.io/gorm"
)

func setupTestService(t *testing.T) (*service.ForwardService, *gorm.DB) {
    db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
    assert.NoError(t, err)

    err = db.AutoMigrate(&model.User{}, &model.Task{}, &model.TaskForward{})
    assert.NoError(t, err)

    userRepo := repository.NewUserRepository(db)
    taskRepo := repository.NewTaskRepository(db)
    forwardRepo := repository.NewForwardRepository(db)

    forwardService := service.NewForwardService(forwardRepo, taskRepo, userRepo, db)

    return forwardService, db
}

func TestForwardTask(t *testing.T) {
    service, db := setupTestService(t)

    // Create users
    user1 := &model.User{Username: "user1", Email: "user1@test.com", Password: "pass"}
    user2 := &model.User{Username: "user2", Email: "user2@test.com", Password: "pass"}
    db.Create(user1)
    db.Create(user2)

    // Create task
    task := &model.Task{UserID: user1.ID, Title: "Test Task"}
    db.Create(task)

    // Forward task
    req := &model.TaskForwardRequest{
        TargetUserIDs: []uint{user2.ID},
        Message:       "Please help",
    }

    response, err := service.ForwardTask(context.Background(), task.ID, req, user1.ID)
    assert.NoError(t, err)
    assert.Equal(t, 1, response.Total)
    assert.Len(t, response.Forwards, 1)
}

func TestForwardTaskToSelf(t *testing.T) {
    service, db := setupTestService(t)

    user1 := &model.User{Username: "user1", Email: "user1@test.com", Password: "pass"}
    db.Create(user1)

    task := &model.Task{UserID: user1.ID, Title: "Test Task"}
    db.Create(task)

    req := &model.TaskForwardRequest{
        TargetUserIDs: []uint{user1.ID},
    }

    _, err := service.ForwardTask(context.Background(), task.ID, req, user1.ID)
    assert.Error(t, err)
    assert.Equal(t, service.ErrForwardToSelf, err)
}
```

- [ ] **Step 3: Run tests**

```bash
go test ./tests/service/forward_service_test.go -v
```

- [ ] **Step 4: Commit**

```bash
git add tests/service/forward_service_test.go
git commit -m "test: add forward service tests"
```

---

## Task 16: Build and Run Integration Test

**Files:**
- None (manual test)

- [ ] **Step 1: Build the application**

```bash
go build -o bin/task_server.exe ./cmd/server
```

Expected: Build succeeds, executable created

- [ ] **Step 2: Run the server**

```bash
./bin/task_server.exe
```

Expected: Server starts without errors on port 8080

- [ ] **Step 3: Test search users endpoint**

```bash
curl -X GET "http://localhost:8080/api/v1/users/search?keyword=test&limit=10"
```

Expected: Returns user list with code 0

- [ ] **Step 4: Test forward task endpoint**

First register and login to get token, then:

```bash
curl -X POST "http://localhost:8080/api/v1/tasks/1/forward" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_user_ids": [2], "message": "Please help"}'
```

Expected: Returns forward response with code 0

- [ ] **Step 5: Test get received forwards**

```bash
curl -X GET "http://localhost:8080/api/v1/forwards/received?page=1&page_size=10" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Expected: Returns received forwards list

- [ ] **Step 6: Test revoke forward**

```bash
curl -X DELETE "http://localhost:8080/api/v1/forwards/1" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason": "No longer needed"}'
```

Expected: Returns success response

- [ ] **Step 7: Commit final changes**

```bash
git add .
git commit -m "feat: complete task forwarding feature implementation"
```

---

## Verification Checklist

Before marking complete, verify:

- [ ] All new files are created
- [ ] All modified files have the correct changes
- [ ] Database migrations run successfully
- [ ] API endpoints respond correctly
- [ ] State synchronization works bidirectionally
- [ ] Forward revocation works with soft delete
- [ ] Circular forward detection works
- [ ] Tests pass
- [ ] Code is formatted with `go fmt`
- [ ] Commits follow conventional commit format

---

## Notes for Implementation

1. **State Sync**: The sync is called asynchronously in TaskService to avoid blocking the main request. This is acceptable for this use case.

2. **Circular Detection**: The forward chain detection limits to 3 levels to prevent infinite loops.

3. **Soft Delete**: Forwarded tasks are soft-deleted when revoked to maintain audit trail.

4. **Error Handling**: Service errors are mapped to appropriate HTTP responses in the handler layer.

5. **Timezone**: All deadline times should be in UTC format (RFC3339).

6. **Testing**: Run tests before committing each task to catch issues early.