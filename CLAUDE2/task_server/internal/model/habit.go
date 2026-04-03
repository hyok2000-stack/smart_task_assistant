package model

import (
	"time"

	"gorm.io/gorm"
)

// Habit 习惯模型
type Habit struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// 用户关联
	UserID uint `gorm:"not null;index" json:"user_id"`
	User   User `json:"user,omitempty"`

	// 识别信息
	HabitID string `gorm:"uniqueIndex:idx_user_habit_id;not null;size:36" json:"habit_id"`
	Title   string `gorm:"not null;size:100" json:"title"`

	// 目标和单位
	TargetCount int    `gorm:"default:1" json:"target_count"`
	Unit        string `gorm:"default:'次';size:10" json:"unit"`

	// 触发配置
	TriggerType     string `gorm:"default:'interval';size:10" json:"trigger_type"` // interval/fixed
	IntervalMinutes *int   `json:"interval_minutes"`
	FixedTime       string `gorm:"size:5" json:"fixed_time"`                        // HH:mm 格式
	ScheduleType    string `gorm:"default:'weekdays';size:10" json:"schedule_type"` // weekdays/daily

	// UI 设置
	IconCode  int  `json:"icon_code"` // Unicode 码点
	SortOrder int  `gorm:"default:0" json:"sort_order"`
	IsEnabled bool `gorm:"default:true" json:"is_enabled"`

	// 提醒方式设置
	SoundEnabled     bool    `gorm:"default:true" json:"sound_enabled"`
	VibrationEnabled bool    `gorm:"default:true" json:"vibration_enabled"`
	VoiceEnabled     bool    `gorm:"default:false" json:"voice_enabled"`
	VoiceText        *string `json:"voice_text"`
	VoiceSpeed       string  `gorm:"default:'normal';size:10" json:"voice_speed"` // slow/normal/fast

	// 打卡习惯专属字段
	ReferenceTime  *string `gorm:"size:5" json:"reference_time"` // HH:mm for clock habits
	AdvanceMinutes *int    `json:"advance_minutes"`              // 提前提醒分钟数

	// 同步
	DeviceID string    `gorm:"index;size:50" json:"device_id"`
	SyncedAt time.Time `gorm:"not null" json:"synced_at"`
}

// CreateHabitRequest 创建习惯请求
type CreateHabitRequest struct {
	HabitID          string  `json:"habit_id" binding:"required"`
	Title            string  `json:"title" binding:"required"`
	TargetCount      int     `json:"target_count"`
	Unit             string  `json:"unit"`
	TriggerType      string  `json:"trigger_type" binding:"required"`
	IntervalMinutes  *int    `json:"interval_minutes"`
	FixedTime        string  `json:"fixed_time"`
	ScheduleType     string  `json:"schedule_type"`
	IconCode         int     `json:"icon_code" binding:"required"`
	SortOrder        int     `json:"sort_order"`
	IsEnabled        bool    `json:"is_enabled"`
	SoundEnabled     bool    `json:"sound_enabled"`
	VibrationEnabled bool    `json:"vibration_enabled"`
	VoiceEnabled     bool    `json:"voice_enabled"`
	VoiceText        *string `json:"voice_text"`
	VoiceSpeed       string  `json:"voice_speed"`
	ReferenceTime    *string `json:"reference_time"`
	AdvanceMinutes   *int    `json:"advance_minutes"`
	DeviceID         string  `json:"device_id"`
}

// UpdateHabitRequest 更新习惯请求
type UpdateHabitRequest struct {
	Title            *string `json:"title"`
	TargetCount      *int    `json:"target_count"`
	Unit             *string `json:"unit"`
	TriggerType      *string `json:"trigger_type"`
	IntervalMinutes  *int    `json:"interval_minutes"`
	FixedTime        *string `json:"fixed_time"`
	ScheduleType     *string `json:"schedule_type"`
	IconCode         *int    `json:"icon_code"`
	SortOrder        *int    `json:"sort_order"`
	IsEnabled        *bool   `json:"is_enabled"`
	SoundEnabled     *bool   `json:"sound_enabled"`
	VibrationEnabled *bool   `json:"vibration_enabled"`
	VoiceEnabled     *bool   `json:"voice_enabled"`
	VoiceText        *string `json:"voice_text"`
	VoiceSpeed       *string `json:"voice_speed"`
	ReferenceTime    *string `json:"reference_time"`
	AdvanceMinutes   *int    `json:"advance_minutes"`
}

// ListHabitsRequest 列出习惯请求
type ListHabitsRequest struct {
	Page      int   `form:"page,default=1"`
	PageSize  int   `form:"page_size,default=20"`
	IsEnabled *bool `form:"is_enabled"`
}

// HabitResponse 习惯响应
type HabitResponse struct {
	Habit
}

// ListHabitsResponse 习惯列表响应
type ListHabitsResponse struct {
	Habits     []HabitResponse `json:"habits"`
	Total      int64           `json:"total"`
	Page       int             `json:"page"`
	PageSize   int             `json:"page_size"`
	TotalPages int             `json:"total_pages"`
}

// SyncHabitsRequest 同步习惯请求
type SyncHabitsRequest struct {
	DeviceID string  `json:"device_id" binding:"required"`
	Habits   []Habit `json:"habits"`
}

// SyncHabitsResponse 同步习惯响应
type SyncHabitsResponse struct {
	SyncedCount int     `json:"synced_count"`
	Habits      []Habit `json:"habits"`
}

// TableName 指定表名
func (Habit) TableName() string {
	return "habits"
}
