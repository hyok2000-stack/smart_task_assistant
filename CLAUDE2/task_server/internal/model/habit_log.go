package model

import (
	"time"

	"gorm.io/gorm"
)

// HabitLog 习惯日志模型
type HabitLog struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// 用户关联
	UserID uint `gorm:"not null;index" json:"user_id"`
	User   User `json:"user,omitempty"`

	// 习惯关联
	HabitID string `gorm:"not null;index:idx_habit_date;size:36" json:"habit_id"`
	Habit   Habit  `json:"habit,omitempty"`

	// 完成数据
	Count       int       `gorm:"default:1" json:"count"`
	Status      int       `gorm:"default:0" json:"status"` // 0: completed, 1: skipped
	CompletedAt time.Time `gorm:"index:idx_habit_date;not null" json:"completed_at"`

	// 同步
	DeviceID string `gorm:"index;size:50" json:"device_id"`
}

// LogCompletionRequest 记录完成请求
type LogCompletionRequest struct {
	Count    int    `json:"count"`
	Status   int    `json:"status"` // 0: completed, 1: skipped
	DeviceID string `json:"device_id"`
}

// ListHabitLogsRequest 列出习惯日志请求
type ListHabitLogsRequest struct {
	Page      int    `form:"page,default=1"`
	PageSize  int    `form:"page_size,default=50"`
	StartDate string `form:"start_date"` // YYYY-MM-DD
	EndDate   string `form:"end_date"`   // YYYY-MM-DD
}

// HabitLogResponse 习惯日志响应
type HabitLogResponse struct {
	HabitLog
}

// ListHabitLogsResponse 习惯日志列表响应
type ListHabitLogsResponse struct {
	Logs       []HabitLogResponse `json:"logs"`
	Total      int64              `json:"total"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
}

// HabitStats 习惯统计
type HabitStats struct {
	TodayProgress int        `json:"today_progress"` // 今日完成数量
	TargetCount   int        `json:"target_count"`   // 每日目标
	Percentage    int        `json:"percentage"`     // 进度百分比
	StreakDays    int        `json:"streak_days"`    // 连续天数
	LastCompleted *time.Time `json:"last_completed"` // 最后完成时间
}

// HabitHistoryItem 习惯历史项
type HabitHistoryItem struct {
	Date   string `json:"date"`   // YYYY-MM-DD
	Count  int    `json:"count"`  // 总完成数
	Status string `json:"status"` // completed/partial/skipped
}

// HabitHistoryResponse 习惯历史响应
type HabitHistoryResponse struct {
	History []HabitHistoryItem `json:"history"`
}

// TableName 指定表名
func (HabitLog) TableName() string {
	return "habit_logs"
}
