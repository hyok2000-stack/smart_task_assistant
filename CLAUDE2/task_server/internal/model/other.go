package model

import (
	"time"

	"gorm.io/gorm"
)

type Tag struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	Name      string         `gorm:"not null" json:"name"`
	Color     string         `json:"color"`
}

type Device struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	DeviceID  string         `gorm:"uniqueIndex;not null" json:"device_id"`
	Name      string         `json:"name"`
	Platform  string         `json:"platform"` // android, ios, web, etc.
	LastSync  time.Time      `json:"last_sync"`
}

// AI 相关模型
type AISuggestion struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	TaskID    uint           `gorm:"index" json:"task_id"`
	Type      string         `json:"type"` // priority, timing, categorization, etc.
	Content   string         `gorm:"type:text" json:"content"`
	Accepted  bool           `gorm:"default:false" json:"accepted"`
}

type AIChatMessage struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	Role      string         `gorm:"not null" json:"role"` // user, assistant, system
	Content   string         `gorm:"type:text;not null" json:"content"`
	TaskID    *uint          `gorm:"index" json:"task_id,omitempty"`
}

type AIChatRequest struct {
	Message string `json:"message" binding:"required"`
	TaskID  *uint  `json:"task_id,omitempty"`
}

type AIChatResponse struct {
	Message string `json:"message"`
	Context string `json:"context,omitempty"`
}

type TaskSuggestionRequest struct {
	TaskTitle    string `json:"task_title" binding:"required"`
	TaskDesc     string `json:"task_desc"`
	SuggestionType string `json:"suggestion_type"` // priority, timing, category
}

type TaskSuggestionResponse struct {
	Suggestion string `json:"suggestion"`
	Reason     string `json:"reason"`
}