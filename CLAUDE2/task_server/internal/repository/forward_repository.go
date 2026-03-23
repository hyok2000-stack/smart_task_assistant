package repository

import (
	"task_server/internal/model"
	"time"

	"gorm.io/gorm"
)

type ForwardRepository struct {
	db *gorm.DB
}

func NewForwardRepository(db *gorm.DB) *ForwardRepository {
	return &ForwardRepository{db: db}
}

func (r *ForwardRepository) Create(forward *model.TaskForward) error {
	return r.db.Create(forward).Error
}

func (r *ForwardRepository) FindByID(id uint) (*model.TaskForward, error) {
	var forward model.TaskForward
	err := r.db.Preload("Forwarder").Preload("Receiver").First(&forward, id).Error
	if err != nil {
		return nil, err
	}
	return &forward, nil
}

func (r *ForwardRepository) FindByTaskID(taskID uint) ([]model.TaskForward, error) {
	var forwards []model.TaskForward
	err := r.db.Preload("Forwarder").Preload("Receiver").Preload("Task").Preload("ForwardedTask").Where("task_id = ?", taskID).Find(&forwards).Error
	return forwards, err
}

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

func (r *ForwardRepository) FindActiveForwardByTaskAndUser(taskID, toUserID uint) (*model.TaskForward, error) {
	var forward model.TaskForward
	err := r.db.Where("task_id = ? AND forwarded_to = ? AND is_active = true", taskID, toUserID).First(&forward).Error
	if err != nil {
		return nil, err
	}
	return &forward, nil
}

func (r *ForwardRepository) FindActiveForwardsByTaskID(taskID uint) ([]model.TaskForward, error) {
	var forwards []model.TaskForward
	err := r.db.Where("task_id = ? AND is_active = true", taskID).Find(&forwards).Error
	return forwards, err
}

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

func (r *ForwardRepository) Revoke(id uint, reason string, revokedAt time.Time) error {
	return r.db.Model(&model.TaskForward{}).Where("id = ?", id).Updates(map[string]interface{}{
		"is_active":      false,
		"revoked_at":     revokedAt,
		"revoked_reason": reason,
	}).Error
}

func (r *ForwardRepository) CheckExpiredForwards() ([]model.TaskForward, error) {
	var forwards []model.TaskForward
	now := time.Now()
	err := r.db.Where("is_expired = false AND deadline < ? AND is_active = true", now).Find(&forwards).Error
	return forwards, err
}

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
