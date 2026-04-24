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
	LocalID     string         `gorm:"size:36" json:"local_id"`                     // 客户端本地 ID
	Title       string         `gorm:"not null" json:"title"`
	Description string         `json:"description"`
	Status      string         `gorm:"size:20;default:'pending'" json:"status"`     // pending, in_progress, completed, cancelled
	Completed   bool           `gorm:"default:false" json:"completed"`
	Priority    int            `gorm:"default:0" json:"priority"`                   // 0: low, 1: medium, 2: high
	DueDate     *time.Time     `json:"due_date"`
	RemindAt    *time.Time     `json:"remind_at"`
	Reminded    bool           `gorm:"default:false" json:"reminded"`
	Category    string         `json:"category"`
	StartTime   *time.Time     `json:"start_time"`                                  // 任务开始时间
	Tags        []Tag          `gorm:"many2many:task_tags;" json:"tags,omitempty"`
	DeviceID    string         `gorm:"index" json:"device_id"`                      // 用于数据同步
	SyncedAt    time.Time      `json:"synced_at"`
	CompletedAt *time.Time     `json:"completed_at"`
	// Recurring and attachment fields
	RecurringRule   string `gorm:"type:text" json:"recurring_rule"`              // 循环规则 (JSON)
	AttachmentPaths string `gorm:"type:text" json:"attachment_paths"`            // 附件路径 (JSON array)
	// Reminder voice fields
	ReminderVoiceEnabled  bool   `gorm:"default:true" json:"reminder_voice_enabled"`
	ReminderVoiceType     string `gorm:"size:20" json:"reminder_voice_type"`
	ReminderVoiceStyle    string `gorm:"size:20" json:"reminder_voice_style"`
	ReminderVoiceSpeed    string `gorm:"size:10" json:"reminder_voice_speed"`
	ReminderCustomVoicePath string `gorm:"type:text" json:"reminder_custom_voice_path"`
	// Forward fields
	IsForwarded  bool  `gorm:"default:false" json:"is_forwarded"`
	ForwardedBy  *uint `json:"forwarded_by"`
	ParentTaskID *uint `gorm:"index" json:"parent_task_id"`
	IsExpired    bool  `gorm:"default:false" json:"is_expired"`
}

type TaskRequest struct {
	Title       string     `json:"title" binding:"required"`
	Description string     `json:"description"`
	LocalID     string     `json:"local_id"`
	Status      string     `json:"status"`
	Completed   *bool      `json:"completed"`
	Priority    int        `json:"priority"`
	DueDate     *time.Time `json:"due_date"`
	RemindAt    *time.Time `json:"remind_at"`
	Category    string     `json:"category"`
	StartTime   *time.Time `json:"start_time"`
	Tags        []string   `json:"tags"`
	DeviceID    string     `json:"device_id"`
	RecurringRule        string `json:"recurring_rule"`
	AttachmentPaths      string `json:"attachment_paths"`
	ReminderVoiceEnabled  *bool  `json:"reminder_voice_enabled"`
	ReminderVoiceType     string `json:"reminder_voice_type"`
	ReminderVoiceStyle    string `json:"reminder_voice_style"`
	ReminderVoiceSpeed    string `json:"reminder_voice_speed"`
	ReminderCustomVoicePath string `json:"reminder_custom_voice_path"`
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
	Status    string `form:"status"`
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
