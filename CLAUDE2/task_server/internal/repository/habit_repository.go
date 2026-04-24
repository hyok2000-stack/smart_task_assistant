package repository

import (
	"errors"

	"task_server/internal/model"
	"task_server/pkg/database"

	"gorm.io/gorm"
)

var (
	// ErrHabitNotFound 习惯未找到
	ErrHabitNotFound = errors.New("habit not found")
	// ErrHabitAlreadyExists 习惯已存在
	ErrHabitAlreadyExists = errors.New("habit with this ID already exists for this user")
)

// HabitRepository 习惯仓库接口
type HabitRepository interface {
	// 基础 CRUD
	Create(habit *model.Habit) error
	FindByID(id uint, userID uint) (*model.Habit, error)
	FindByHabitID(habitID string, userID uint) (*model.Habit, error)
	FindByUserID(userID uint) ([]*model.Habit, error)
	Update(habit *model.Habit) error
	Delete(id uint, userID uint) error
	DeleteByHabitID(habitID string, userID uint) error

	// 切换启用状态
	ToggleEnabled(habitID string, userID uint) error

	// 查询
	CountByUserID(userID uint) (int64, error)
	FindEnabledByUserID(userID uint) ([]*model.Habit, error)

	// 同步操作
	UpsertByDeviceID(habit *model.Habit) error
	FindByDeviceID(deviceID string, userID uint) ([]*model.Habit, error)

	// 批量操作
	BulkUpsert(habits []*model.Habit) error
}

// habitRepository 习惯仓库实现
type habitRepository struct {
	db *gorm.DB
}

// NewHabitRepository 创建习惯仓库
func NewHabitRepository() HabitRepository {
	return &habitRepository{
		db: database.GetDB(),
	}
}

// Create 创建习惯
func (r *habitRepository) Create(habit *model.Habit) error {
	return r.db.Create(habit).Error
}

// FindByID 根据数据库 ID 查找习惯
func (r *habitRepository) FindByID(id uint, userID uint) (*model.Habit, error) {
	var habit model.Habit
	err := r.db.Where("id = ? AND user_id = ?", id, userID).First(&habit).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrHabitNotFound
		}
		return nil, err
	}
	return &habit, nil
}

// FindByHabitID 根据 HabitID 查找习惯
func (r *habitRepository) FindByHabitID(habitID string, userID uint) (*model.Habit, error) {
	var habit model.Habit
	err := r.db.Where("habit_id = ? AND user_id = ?", habitID, userID).First(&habit).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrHabitNotFound
		}
		return nil, err
	}
	return &habit, nil
}

// FindByUserID 查找用户的所有习惯
func (r *habitRepository) FindByUserID(userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("user_id = ?", userID).Order("sort_order ASC").Find(&habits).Error
	return habits, err
}

// Update 更新习惯
func (r *habitRepository) Update(habit *model.Habit) error {
	return r.db.Save(habit).Error
}

// Delete 删除习惯（软删除）
func (r *habitRepository) Delete(id uint, userID uint) error {
	result := r.db.Where("id = ? AND user_id = ?", id, userID).Delete(&model.Habit{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return nil
}

// DeleteByHabitID 根据 HabitID 删除习惯（软删除）
func (r *habitRepository) DeleteByHabitID(habitID string, userID uint) error {
	result := r.db.Where("habit_id = ? AND user_id = ?", habitID, userID).Delete(&model.Habit{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return nil
}

// ToggleEnabled 切换启用状态
func (r *habitRepository) ToggleEnabled(habitID string, userID uint) error {
	result := r.db.Model(&model.Habit{}).
		Where("habit_id = ? AND user_id = ?", habitID, userID).
		Update("is_enabled", gorm.Expr("NOT is_enabled"))

	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrHabitNotFound
	}
	return nil
}

// UpsertByDeviceID 根据 DeviceID 更新或插入习惯（用于同步）
func (r *habitRepository) UpsertByDeviceID(habit *model.Habit) error {
	var existing model.Habit
	err := r.db.Where("habit_id = ? AND user_id = ?", habit.HabitID, habit.UserID).First(&existing).Error

	if err == nil {
		// 已存在，更新（使用 synced_at 进行冲突解决）
		if habit.SyncedAt.After(existing.SyncedAt) {
			habit.ID = existing.ID
			return r.db.Save(habit).Error
		}
		return nil // 服务器版本更新，跳过
	}

	if errors.Is(err, gorm.ErrRecordNotFound) {
		// 不存在，插入
		return r.db.Create(habit).Error
	}

	return err
}

// FindByDeviceID 根据 DeviceID 查找习惯
func (r *habitRepository) FindByDeviceID(deviceID string, userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("device_id = ? AND user_id = ?", deviceID, userID).Find(&habits).Error
	return habits, err
}

// BulkUpsert 批量更新或插入习惯
func (r *habitRepository) BulkUpsert(habits []*model.Habit) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		for _, habit := range habits {
			var existing model.Habit
			err := tx.Where("habit_id = ? AND user_id = ?", habit.HabitID, habit.UserID).First(&existing).Error

			if err == nil {
				// 已存在，更新（使用 synced_at 进行冲突解决）
				if habit.SyncedAt.After(existing.SyncedAt) {
					habit.ID = existing.ID
					if err := tx.Save(habit).Error; err != nil {
						return err
					}
				}
			} else if errors.Is(err, gorm.ErrRecordNotFound) {
				// 不存在，插入
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

// CountByUserID 统计用户习惯数量
func (r *habitRepository) CountByUserID(userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.Habit{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

// FindEnabledByUserID 查找用户启用的习惯
func (r *habitRepository) FindEnabledByUserID(userID uint) ([]*model.Habit, error) {
	var habits []*model.Habit
	err := r.db.Where("user_id = ? AND is_enabled = ?", userID, true).
		Order("sort_order ASC").
		Find(&habits).Error
	return habits, err
}
