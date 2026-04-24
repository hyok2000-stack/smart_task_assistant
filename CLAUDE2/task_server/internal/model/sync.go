package model

import (
	"time"
)

// SyncPushRequest 客户端推送本地变更请求
type SyncPushRequest struct {
	DeviceID   string              `json:"device_id" binding:"required"`
	Tasks      []SyncTask          `json:"tasks"`
	Tags       []SyncTag           `json:"tags"`
	Habits     []SyncHabitData     `json:"habits"`
	HabitLogs  []SyncHabitLogData  `json:"habit_logs"`
}

// SyncTask simplified task for sync
type SyncTask struct {
	ID          uint   `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Priority    int    `json:"priority"`
	Category    string `json:"category"`
	Completed   bool   `json:"completed"`
	DueTime     string `json:"due_time"`
	UpdatedAt   string `json:"updated_at"`
}

// SyncTag simplified tag for sync
type SyncTag struct {
	ID        uint   `json:"id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	UpdatedAt string `json:"updated_at"`
}

// SyncHabitData simplified habit for sync
type SyncHabitData struct {
	ID              uint   `json:"id"`
	Name            string `json:"name"`
	HabitType       string `json:"habit_type"`
	TriggerType     string `json:"trigger_type"`
	IntervalMinutes int    `json:"interval_minutes"`
	FixedTime       string `json:"fixed_time"`
	IsActive        bool   `json:"is_active"`
	UpdatedAt       string `json:"updated_at"`
}

// SyncHabitLogData simplified habit log for sync
type SyncHabitLogData struct {
	ID          uint   `json:"id"`
	HabitID     uint   `json:"habit_id"`
	Count       int    `json:"count"`
	Status      string `json:"status"`
	CompletedAt string `json:"completed_at"`
}

// SyncPushResponse 推送响应
type SyncPushResponse struct {
	Success       bool           `json:"success"`
	SyncedAt      time.Time      `json:"synced_at"`
	TasksCreated  int            `json:"tasks_created"`
	TasksUpdated  int            `json:"tasks_updated"`
	TagsCreated   int            `json:"tags_created"`
	TagsUpdated   int            `json:"tags_updated"`
	HabitsCreated int            `json:"habits_created"`
	HabitsUpdated int            `json:"habits_updated"`
	LogsCreated   int            `json:"logs_created"`
	LogsUpdated   int            `json:"logs_updated"`
	Conflicts     []SyncConflict `json:"conflicts,omitempty"`
}

// SyncPullRequest 拉取请求
type SyncPullRequest struct {
	DeviceID string    `json:"device_id" binding:"required"`
	LastSync time.Time `json:"last_sync"`
	Tables   []string  `json:"tables"` // tasks, tags, habits, habit_logs
}

// SyncPullResponse 拉取响应
type SyncPullResponse struct {
	DeviceID  string     `json:"device_id"`
	SyncedAt  time.Time  `json:"synced_at"`
	Tasks     []Task     `json:"tasks,omitempty"`
	Tags      []Tag      `json:"tags,omitempty"`
	Habits    []Habit    `json:"habits,omitempty"`
	HabitLogs []HabitLog `json:"habit_logs,omitempty"`
}

// SyncStatusResponse 同步状态响应
type SyncStatusResponse struct {
	LastSyncTime *time.Time `json:"last_sync_time,omitempty"`
	DeviceID     string     `json:"device_id"`
	TaskCount    int64      `json:"task_count"`
	TagCount     int64      `json:"tag_count"`
	HabitCount   int64      `json:"habit_count"`
	LogCount     int64      `json:"log_count"`
}

// SyncConflict 同步冲突
type SyncConflict struct {
	Type     string    `json:"type"` // task, tag, habit, habit_log
	ID       uint      `json:"id"`
	LocalAt  time.Time `json:"local_updated_at"`
	RemoteAt time.Time `json:"remote_updated_at"`
	Reason   string    `json:"reason"`
}

// SyncRecord 同步记录
type SyncRecord struct {
	ID        uint       `gorm:"primarykey" json:"id"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	DeletedAt *time.Time `gorm:"index" json:"deleted_at,omitempty"`

	UserID      uint    `gorm:"not null;index" json:"user_id"`
	DeviceID    string  `gorm:"not null;index:idx_sync_user_device" json:"device_id"`
	SyncType    string  `gorm:"not null" json:"sync_type"` // push, pull
	TableName   string  `json:"table_name"`
	RecordCount int     `json:"record_count"`
	Status      string  `gorm:"default:'success'" json:"status"` // success, failed, partial
	ErrorMsg    *string `json:"error_msg,omitempty"`
}
