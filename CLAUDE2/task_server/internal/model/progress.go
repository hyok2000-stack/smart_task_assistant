package model

import (
	"time"

	"gorm.io/gorm"
)

// TaskProgress represents the progress tracking for forwarded tasks
type TaskProgress struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	TaskID          uint   `gorm:"not null;index:idx_task_progress_task" json:"task_id"`
	ForwardID       uint   `gorm:"not null;index:idx_task_progress_forward" json:"forward_id"`
	AssignedTo      uint   `gorm:"not null;index" json:"assigned_to"`
	Status          string `gorm:"default:'pending';index" json:"status"` // pending, in_progress, completed, rejected
	ProgressPercent int    `gorm:"default:0" json:"progress_percent"`
	Feedback        string `gorm:"type:text" json:"feedback"`

	// Associations
	Forward TaskForward `gorm:"foreignKey:ForwardID" json:"-"`
}

// UpdateProgressRequest is the request for updating task progress
type UpdateProgressRequest struct {
	Status          string `json:"status" binding:"required,oneof=pending in_progress completed rejected"`
	ProgressPercent int    `json:"progress_percent" binding:"min=0,max=100"`
	Feedback        string `json:"feedback" binding:"max=1000"`
}

// ProgressResponse is the response for task progress
type ProgressResponse struct {
	ID              uint      `json:"id"`
	TaskID          uint      `json:"task_id"`
	ForwardID       uint      `json:"forward_id"`
	AssignedTo      uint      `json:"assigned_to"`
	Status          string    `json:"status"`
	ProgressPercent int       `json:"progress_percent"`
	Feedback        string    `json:"feedback"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// SubmitFeedbackRequest is the request for submitting feedback
type SubmitFeedbackRequest struct {
	Feedback string `json:"feedback" binding:"required,max=1000"`
}
