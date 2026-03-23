package service

import (
	"context"
	"errors"
	"task_server/internal/model"
	"task_server/internal/repository"
	"time"

	"gorm.io/gorm"
)

var (
	ErrTaskNotFound     = errors.New("task not found")
	ErrUserNotFound     = errors.New("user not found")
	ErrNoPermission     = errors.New("no permission")
	ErrForwardToSelf    = errors.New("cannot forward to self")
	ErrAlreadyForwarded = errors.New("already forwarded to this user")
	ErrCircularForward  = errors.New("circular forward detected")
	ErrForwardRevoked   = errors.New("forward already revoked")
	ErrExceedLimit      = errors.New("exceed forward limit")
	ErrInvalidDeadline  = errors.New("invalid deadline")
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

	// Validate forward limit
	if len(req.TargetUserIDs) > 10 {
		return nil, ErrExceedLimit
	}

	// Get sender user
	sender, err := s.userRepo.FindByID(userID)
	if err != nil {
		return nil, ErrUserNotFound
	}

	// Verify target users exist
	var users []model.User
	for _, targetUserID := range req.TargetUserIDs {
		if targetUserID == userID {
			return nil, ErrForwardToSelf
		}

		user, err := s.userRepo.FindByID(targetUserID)
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
				// Already forwarded to this user, skip
				continue
			}

			// Copy task for receiver
			forwardedTask := &model.Task{
				UserID:       targetUserID,
				Title:        task.Title,
				Description:  task.Description,
				Completed:    task.Completed,
				Priority:     task.Priority,
				DueDate:      task.DueDate,
				RemindAt:     task.RemindAt,
				Category:     task.Category,
				IsForwarded:  true,
				ForwardedBy:  &userID,
				ParentTaskID: &taskID,
				IsExpired:    false,
				SyncedAt:     time.Now(),
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
				ForwardedBy:     *sender,
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
	if err := s.taskRepo.Delete(forward.ForwardedTaskID); err != nil {
		return err
	}

	return nil
}

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
