package repository

import (
	"task_server/internal/model"

	"gorm.io/gorm"
)

type TaskRepository struct {
	db *gorm.DB
}

func NewTaskRepository(db *gorm.DB) *TaskRepository {
	return &TaskRepository{db: db}
}

// Create 创建任务
func (r *TaskRepository) Create(task *model.Task) error {
	return r.db.Create(task).Error
}

// FindByID 根据 ID 查找任务
func (r *TaskRepository) FindByID(id uint) (*model.Task, error) {
	var task model.Task
	err := r.db.Preload("Tags").First(&task, id).Error
	if err != nil {
		return nil, err
	}
	return &task, nil
}

// FindByUserID 根据用户 ID 查找任务列表
func (r *TaskRepository) FindByUserID(userID uint, offset, limit int, filters map[string]interface{}) ([]model.Task, int64, error) {
	var tasks []model.Task
	var total int64

	query := r.db.Model(&model.Task{}).Where("user_id = ?", userID)

	// 应用过滤条件
	if completed, ok := filters["completed"]; ok {
		query = query.Where("completed = ?", completed)
	}
	if priority, ok := filters["priority"]; ok {
		query = query.Where("priority = ?", priority)
	}
	if category, ok := filters["category"]; ok && category != "" {
		query = query.Where("category = ?", category)
	}
	if keyword, ok := filters["keyword"]; ok && keyword != "" {
		query = query.Where("title LIKE ? OR description LIKE ?", "%"+keyword.(string)+"%", "%"+keyword.(string)+"%")
	}

	// 获取总数
	err := query.Count(&total).Error
	if err != nil {
		return nil, 0, err
	}

	// 分页查询
	err = query.Preload("Tags").Offset(offset).Limit(limit).Order("created_at DESC").Find(&tasks).Error
	if err != nil {
		return nil, 0, err
	}

	return tasks, total, nil
}

// Update 更新任务
func (r *TaskRepository) Update(task *model.Task) error {
	return r.db.Save(task).Error
}

// Delete 删除任务
func (r *TaskRepository) Delete(id uint) error {
	return r.db.Delete(&model.Task{}, id).Error
}

// GetStats 获取任务统计
func (r *TaskRepository) GetStats(userID uint) (*model.TaskStats, error) {
	stats := &model.TaskStats{}

	// 总数
	r.db.Model(&model.Task{}).Where("user_id = ?", userID).Count(&stats.Total)

	// 已完成
	r.db.Model(&model.Task{}).Where("user_id = ? AND completed = ?", userID, true).Count(&stats.Completed)

	// 待完成
	stats.Pending = stats.Total - stats.Completed

	// 高优先级
	r.db.Model(&model.Task{}).Where("user_id = ? AND priority = ? AND completed = ?", userID, 2, false).Count(&stats.HighPriority)

	// 已过期
	r.db.Model(&model.Task{}).Where("user_id = ? AND due_date < ? AND completed = ?", userID, gorm.Expr("NOW()"), false).Count(&stats.Overdue)

	// 本周
	r.db.Model(&model.Task{}).Where("user_id = ? AND due_date >= ? AND due_date <= ?", userID, gorm.Expr("DATE_SUB(NOW(), INTERVAL WEEKDAY(NOW()) DAY)"), gorm.Expr("DATE_ADD(NOW(), INTERVAL 6-WEEKDAY(NOW()) DAY)")).Count(&stats.ThisWeek)

	// 本月
	r.db.Model(&model.Task{}).Where("user_id = ? AND due_date >= ? AND due_date <= ?", userID, gorm.Expr("DATE_FORMAT(NOW(), '%Y-%m-01')"), gorm.Expr("LAST_DAY(NOW())")).Count(&stats.ThisMonth)

	return stats, nil
}

// FindPendingReminders 查找待提醒的任务
func (r *TaskRepository) FindPendingReminders() ([]model.Task, error) {
	var tasks []model.Task
	err := r.db.Where("remind_at <= ? AND reminded = ?", gorm.Expr("NOW()"), false).Find(&tasks).Error
	return tasks, err
}

// UpdateReminded 更新任务已提醒状态
func (r *TaskRepository) UpdateReminded(taskID uint) error {
	return r.db.Model(&model.Task{}).Where("id = ?", taskID).Update("reminded", true).Error
}