package repository

import (
	"errors"
	"time"

	"task_server/internal/model"
	"task_server/pkg/database"

	"gorm.io/gorm"
)

var (
	// ErrHabitLogNotFound 习惯日志未找到
	ErrHabitLogNotFound = errors.New("habit log not found")
)

// HabitLogRepository 习惯日志仓库接口
type HabitLogRepository interface {
	// 基础 CRUD
	Create(log *model.HabitLog) error
	FindByID(id uint, userID uint) (*model.HabitLog, error)

	// 根据习惯查询
	FindByHabitID(habitID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error)
	GetTodayCount(habitID string, userID uint) (int, error)

	// 日期范围查询
	GetDateRangeLogs(habitID string, userID uint, start, end time.Time) ([]*model.HabitLog, error)
	GetDateRangeCount(habitID string, userID uint, start, end time.Time, status int) (int, error)

	// 历史记录查询
	GetUniqueCompletionDates(habitID string, userID uint, days int) ([]time.Time, error)
	GetDailyStatsForDateRange(habitID string, userID uint, start, end time.Time) ([]DailyStat, error)
	GetLastCompletedTime(habitID string, userID uint) (*time.Time, error)

	// 统计
	CountTotalLogs(habitID string, userID uint) (int64, error)

	// 同步操作
	UpsertByDeviceID(log *model.HabitLog) error
	FindByDeviceID(deviceID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error)
}

// habitLogRepository 习惯日志仓库实现
type habitLogRepository struct {
	db *gorm.DB
}

// NewHabitLogRepository 创建习惯日志仓库
func NewHabitLogRepository() HabitLogRepository {
	return &habitLogRepository{
		db: database.GetDB(),
	}
}

// Create 创建日志
func (r *habitLogRepository) Create(log *model.HabitLog) error {
	return r.db.Create(log).Error
}

// FindByID 根据 ID 查找日志
func (r *habitLogRepository) FindByID(id uint, userID uint) (*model.HabitLog, error) {
	var log model.HabitLog
	err := r.db.Where("id = ? AND user_id = ?", id, userID).First(&log).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrHabitLogNotFound
		}
		return nil, err
	}
	return &log, nil
}

// FindByHabitID 根据习惯 ID 查询日志（分页）
func (r *habitLogRepository) FindByHabitID(habitID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error) {
	var logs []*model.HabitLog
	var total int64

	offset := (page - 1) * pageSize

	// 查询总数
	if err := r.db.Model(&model.HabitLog{}).
		Where("habit_id = ? AND user_id = ?", habitID, userID).
		Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// 查询数据
	err := r.db.Where("habit_id = ? AND user_id = ?", habitID, userID).
		Order("completed_at DESC").
		Limit(pageSize).
		Offset(offset).
		Find(&logs).Error

	return logs, total, err
}

// GetTodayCount 获取今日完成数量
func (r *habitLogRepository) GetTodayCount(habitID string, userID uint) (int, error) {
	now := time.Now().UTC()
	startOfDay := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	endOfDay := startOfDay.Add(24 * time.Hour)

	var count int64
	err := r.db.Model(&model.HabitLog{}).
		Where("habit_id = ? AND user_id = ? AND completed_at >= ? AND completed_at < ? AND status = ?",
			habitID, userID, startOfDay, endOfDay, 0).
		Select("COALESCE(SUM(count), 0)").
		Scan(&count).Error

	return int(count), err
}

// GetDateRangeLogs 获取日期范围内的日志
func (r *habitLogRepository) GetDateRangeLogs(habitID string, userID uint, start, end time.Time) ([]*model.HabitLog, error) {
	var logs []*model.HabitLog
	err := r.db.Where("habit_id = ? AND user_id = ? AND completed_at >= ? AND completed_at < ?",
		habitID, userID, start, end).
		Order("completed_at DESC").
		Find(&logs).Error
	return logs, err
}

// GetDateRangeCount 获取日期范围内的完成数量
func (r *habitLogRepository) GetDateRangeCount(habitID string, userID uint, start, end time.Time, status int) (int, error) {
	var count int64
	err := r.db.Model(&model.HabitLog{}).
		Where("habit_id = ? AND user_id = ? AND completed_at >= ? AND completed_at < ? AND status = ?",
			habitID, userID, start, end, status).
		Select("COALESCE(SUM(count), 0)").
		Scan(&count).Error

	return int(count), err
}

// GetUniqueCompletionDates 获取唯一的完成日期（用于计算连续天数）
func (r *habitLogRepository) GetUniqueCompletionDates(habitID string, userID uint, days int) ([]time.Time, error) {
	now := time.Now().UTC()
	startDate := now.AddDate(0, 0, -days)
	startOfDay := time.Date(startDate.Year(), startDate.Month(), startDate.Day(), 0, 0, 0, 0, time.UTC)

	var dates []time.Time

	err := r.db.Model(&model.HabitLog{}).
		Select("DISTINCT DATE(completed_at) as date").
		Where("habit_id = ? AND user_id = ? AND completed_at >= ? AND status = ?",
			habitID, userID, startOfDay, 0).
		Order("date DESC").
		Pluck("date", &dates).Error

	return dates, err
}

// UpsertByDeviceID 根据 DeviceID 更新或插入日志（用于同步）
func (r *habitLogRepository) UpsertByDeviceID(log *model.HabitLog) error {
	// 日志通常不需要更新，只插入不存在的记录
	var count int64
	err := r.db.Model(&model.HabitLog{}).
		Where("habit_id = ? AND user_id = ? AND completed_at = ?",
			log.HabitID, log.UserID, log.CompletedAt).
		Count(&count).Error

	if err != nil {
		return err
	}

	if count == 0 {
		return r.db.Create(log).Error
	}

	return nil // 已存在，跳过
}

// FindByDeviceID 根据 DeviceID 查找日志（分页）
func (r *habitLogRepository) FindByDeviceID(deviceID string, userID uint, page, pageSize int) ([]*model.HabitLog, int64, error) {
	var logs []*model.HabitLog
	var total int64

	offset := (page - 1) * pageSize

	// 查询总数
	if err := r.db.Model(&model.HabitLog{}).
		Where("device_id = ? AND user_id = ?", deviceID, userID).
		Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// 查询数据
	err := r.db.Where("device_id = ? AND user_id = ?", deviceID, userID).
		Order("completed_at DESC").
		Limit(pageSize).
		Offset(offset).
		Find(&logs).Error

	return logs, total, err
}

// DailyStat 每日统计数据结构（用于类型安全扫描）
type DailyStat struct {
	Date   string `json:"date"`
	Count  int64  `json:"count"`
	Status int64  `json:"status"`
}

// GetDailyStatsForDateRange 获取日期范围内每天的统计
func (r *habitLogRepository) GetDailyStatsForDateRange(habitID string, userID uint, start, end time.Time) ([]DailyStat, error) {
	var results []DailyStat

	err := r.db.Model(&model.HabitLog{}).
		Select("DATE(completed_at) as date, COALESCE(SUM(count), 0) as count, COALESCE(MIN(status), 0) as status").
		Where("habit_id = ? AND user_id = ? AND completed_at >= ? AND completed_at < ?",
			habitID, userID, start, end).
		Group("DATE(completed_at)").
		Order("date DESC").
		Scan(&results).Error

	return results, err
}

// CountTotalLogs 统计总日志数量
func (r *habitLogRepository) CountTotalLogs(habitID string, userID uint) (int64, error) {
	var count int64
	err := r.db.Model(&model.HabitLog{}).
		Where("habit_id = ? AND user_id = ?", habitID, userID).
		Count(&count).Error
	return count, err
}

// GetLastCompletedTime 获取最后完成时间
func (r *habitLogRepository) GetLastCompletedTime(habitID string, userID uint) (*time.Time, error) {
	var completedAt time.Time
	err := r.db.Model(&model.HabitLog{}).
		Select("MAX(completed_at)").
		Where("habit_id = ? AND user_id = ? AND status = ?", habitID, userID, 0).
		Scan(&completedAt).Error

	if err != nil || completedAt.IsZero() {
		return nil, err
	}

	return &completedAt, nil
}
