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
	LocalID   string         `gorm:"size:36" json:"local_id"`           // 客户端本地 ID
	Name      string         `gorm:"not null" json:"name"`
	Color     string         `json:"color"`
	Icon      string         `json:"icon"`                              // 标签图标
	SortOrder int            `gorm:"default:0" json:"sort_order"`       // 排序
	IsDefault bool           `gorm:"default:false" json:"is_default"`   // 是否为默认标签
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
	TaskTitle      string `json:"task_title" binding:"required"`
	TaskDesc       string `json:"task_desc"`
	SuggestionType string `json:"suggestion_type"` // priority, timing, category
}

type TaskSuggestionResponse struct {
	Suggestion string `json:"suggestion"`
	Reason     string `json:"reason"`
}

// TaskForward represents a task forwarding relationship with bidirectional sync
type TaskForward struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	TaskID          uint       `gorm:"not null;index:idx_task_forwards_task_id" json:"task_id"`
	ForwardedTaskID uint       `gorm:"not null;index:idx_task_forwards_forwarded_task_id" json:"forwarded_task_id"`
	ForwardedBy     uint       `gorm:"not null;index:idx_task_forwards_forwarded_by" json:"forwarded_by"`
	ForwardedTo     uint       `gorm:"not null;index:idx_task_forwards_forwarded_to" json:"forwarded_to"`
	Message         string     `gorm:"type:text" json:"message"`
	Deadline        *time.Time `json:"deadline"`
	IsExpired       bool       `gorm:"default:false" json:"is_expired"`
	IsActive        bool       `gorm:"default:true;index:idx_task_forwards_is_active" json:"is_active"`
	RevokedAt       *time.Time `json:"revoked_at"`
	RevokedReason   string     `gorm:"type:text" json:"revoked_reason"`

	// Associations
	Forwarder     User `gorm:"foreignKey:ForwardedBy"`
	Receiver      User `gorm:"foreignKey:ForwardedTo"`
	Task          Task `gorm:"foreignKey:TaskID"`
	ForwardedTask Task `gorm:"foreignKey:ForwardedTaskID"`
}

// TaskForwardRequest is the request for forwarding a task (sync-based)
type TaskForwardRequest struct {
	TargetUserIDs []uint `json:"target_user_ids" binding:"required,min=1,max=10"`
	Message       string `json:"message" binding:"max=500"`
	Deadline      string `json:"deadline"` // ISO 8601 format
}

// TaskForwardResponse is the response for a forward
type TaskForwardResponse struct {
	ID              uint       `json:"id"`
	ForwardedTaskID uint       `json:"forwarded_task_id"`
	TaskID          uint       `json:"task_id"`
	ForwardedBy     User       `json:"forwarded_by"`
	ForwardedTo     User       `json:"forwarded_to"`
	Message         string     `json:"message"`
	Deadline        *time.Time `json:"deadline"`
	IsExpired       bool       `json:"is_expired"`
	IsActive        bool       `json:"is_active"`
	CreatedAt       time.Time  `json:"created_at"`
}

// TaskForwardListResponse is the response for listing forwards
type TaskForwardListResponse struct {
	Forwards []TaskForwardResponse `json:"forwards"`
	Total    int                   `json:"total"`
}

// RevokeForwardRequest is the request for revoking a forward
type RevokeForwardRequest struct {
	Reason string `json:"reason" binding:"max=200"`
}

// SearchUsersRequest is the request for searching users
type SearchUsersRequest struct {
	Keyword string `form:"keyword" binding:"required,min=1"`
	Limit   int    `form:"limit,default=10"`
}

// SearchUsersResponse is the response for searching users
type SearchUsersResponse struct {
	Users []User `json:"users"`
	Total int    `json:"total"`
}

// ForwardRecordResponse is the response for forward records
type ForwardRecordResponse struct {
	ID              uint       `json:"id"`
	TaskID          uint       `json:"task_id"`
	ForwardedTaskID uint       `json:"forwarded_task_id"`
	ForwardedBy     uint       `json:"forwarded_by"`
	ForwardedTo     uint       `json:"forwarded_to"`
	Message         string     `json:"message"`
	Deadline        *time.Time `json:"deadline"`
	IsExpired       bool       `json:"is_expired"`
	IsActive        bool       `json:"is_active"`
	RevokedAt       *time.Time `json:"revoked_at"`
	CreatedAt       time.Time  `json:"created_at"`
}
