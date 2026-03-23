package model

import (
	"time"

	"gorm.io/gorm"
)

type Task struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
	UserID      uint           `gorm:"not null;index" json:"user_id"`
	User        User           `json:"user,omitempty"`
	Title       string         `gorm:"not null" json:"title"`
	Description string         `json:"description"`
	Completed   bool           `gorm:"default:false" json:"completed"`
	Priority    int            `gorm:"default:0" json:"priority"` // 0: low, 1: medium, 2: high
	DueDate     *time.Time     `json:"due_date"`
	RemindAt    *time.Time     `json:"remind_at"`
	Reminded    bool           `gorm:"default:false" json:"reminded"`
	Category    string         `json:"category"`
	Tags        []Tag          `gorm:"many2many:task_tags;" json:"tags,omitempty"`
	DeviceID    string         `gorm:"index" json:"device_id"` // 用于数据同步
	SyncedAt    time.Time      `json:"synced_at"`
	CompletedAt *time.Time     `json:"completed_at"`
	// Forward fields
	IsForwarded  bool  `gorm:"default:false" json:"is_forwarded"`
	ForwardedBy  *uint `json:"forwarded_by"`
	ParentTaskID *uint `gorm:"index" json:"parent_task_id"`
	IsExpired    bool  `gorm:"default:false" json:"is_expired"`
}

type TaskRequest struct {
	Title       string     `json:"title" binding:"required"`
	Description string     `json:"description"`
	Completed   *bool      `json:"completed"`
	Priority    int        `json:"priority"`
	DueDate     *time.Time `json:"due_date"`
	RemindAt    *time.Time `json:"remind_at"`
	Category    string     `json:"category"`
	Tags        []string   `json:"tags"`
}

type TaskResponse struct {
	Task
	Tags []Tag `json:"tags"`
}

type TaskListRequest struct {
	Page      int    `form:"page,default=1"`
	PageSize  int    `form:"page_size,default=10"`
	Completed *bool  `form:"completed"`
	Priority  *int   `form:"priority"`
	Category  string `form:"category"`
	Keyword   string `form:"keyword"`
	StartDate string `form:"start_date"`
	EndDate   string `form:"end_date"`
}

type TaskListResponse struct {
	Tasks      []TaskResponse `json:"tasks"`
	Total      int64          `json:"total"`
	Page       int            `json:"page"`
	PageSize   int            `json:"page_size"`
	TotalPages int            `json:"total_pages"`
}

type TaskStats struct {
	Total        int64 `json:"total"`
	Completed    int64 `json:"completed"`
	Pending      int64 `json:"pending"`
	HighPriority int64 `json:"high_priority"`
	Overdue      int64 `json:"overdue"`
	ThisWeek     int64 `json:"this_week"`
	ThisMonth    int64 `json:"this_month"`
}
