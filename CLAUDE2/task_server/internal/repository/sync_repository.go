package repository

import (
	"task_server/internal/model"
	"time"

	"gorm.io/gorm"
)

type SyncRepository struct {
	db *gorm.DB
}

func NewSyncRepository(db *gorm.DB) *SyncRepository {
	return &SyncRepository{db: db}
}

func (r *SyncRepository) PullTasks(userID uint, since time.Time) ([]model.Task, error) {
	var tasks []model.Task
	err := r.db.Where("user_id = ? AND updated_at > ?", userID, since).Order("updated_at DESC").Find(&tasks).Error
	return tasks, err
}

func (r *SyncRepository) PullTags(userID uint, since time.Time) ([]model.Tag, error) {
	var tags []model.Tag
	err := r.db.Where("user_id = ? AND updated_at > ?", userID, since).Order("updated_at DESC").Find(&tags).Error
	return tags, err
}

func (r *SyncRepository) PullHabits(userID uint, since time.Time) ([]model.Habit, error) {
	var habits []model.Habit
	err := r.db.Where("user_id = ? AND updated_at > ?", userID, since).Order("updated_at DESC").Find(&habits).Error
	return habits, err
}

func (r *SyncRepository) PullHabitLogs(userID uint, since time.Time) ([]model.HabitLog, error) {
	var logs []model.HabitLog
	err := r.db.Joins("JOIN habits ON habits.id = habit_logs.habit_id").
		Where("habits.user_id = ? AND habit_logs.updated_at > ?", userID, since).
		Order("habit_logs.updated_at DESC").Find(&logs).Error
	return logs, err
}

func (r *SyncRepository) CountTasks(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.Task{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *SyncRepository) CountTags(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.Tag{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *SyncRepository) CountHabits(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *SyncRepository) CountHabitLogs(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.HabitLog{}).
		Joins("JOIN habits ON habits.id = habit_logs.habit_id").
		Where("habits.user_id = ?", userID).Count(&count).Error
	return count, err
}

func (r *SyncRepository) RecordSync(record *model.SyncRecord) error {
	return r.db.Create(record).Error
}

func (r *SyncRepository) GetLastSyncTime(userID uint, deviceID string) (*time.Time, error) {
	var record model.SyncRecord
	err := r.db.Where("user_id = ? AND device_id = ? AND status = ?", userID, deviceID, "success").
		Order("created_at DESC").First(&record).Error
	if err != nil {
		return nil, nil
	}
	return &record.CreatedAt, nil
}
