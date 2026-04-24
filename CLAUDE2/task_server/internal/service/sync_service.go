package service

import (
	"fmt"
	"task_server/internal/model"
	"task_server/internal/repository"
	"time"

	"go.uber.org/zap"
	"gorm.io/gorm"
)

type SyncService struct {
	syncRepo  *repository.SyncRepository
	taskRepo  *repository.TaskRepository
	tagRepo   *repository.TagRepository
	habitRepo repository.HabitRepository
	db        *gorm.DB
}

func NewSyncService(
	syncRepo *repository.SyncRepository,
	taskRepo *repository.TaskRepository,
	tagRepo *repository.TagRepository,
	habitRepo repository.HabitRepository,
	db *gorm.DB,
) *SyncService {
	return &SyncService{
		syncRepo:  syncRepo,
		taskRepo:  taskRepo,
		tagRepo:   tagRepo,
		habitRepo: habitRepo,
		db:        db,
	}
}

// Pull pulls incremental data since lastSync
func (s *SyncService) Pull(userID uint, req *model.SyncPullRequest) (*model.SyncPullResponse, error) {
	resp := &model.SyncPullResponse{
		DeviceID: req.DeviceID,
		SyncedAt: time.Now(),
	}

	tables := req.Tables
	if len(tables) == 0 {
		tables = []string{"tasks", "tags", "habits", "habit_logs"}
	}

	since := req.LastSync
	// If lastSync is zero, return all data
	if since.IsZero() {
		since = time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	}

	for _, table := range tables {
		switch table {
		case "tasks":
			tasks, err := s.syncRepo.PullTasks(userID, since)
			if err != nil {
				zap.L().Error("Failed to pull tasks", zap.Error(err))
				continue
			}
			resp.Tasks = tasks
		case "tags":
			tags, err := s.syncRepo.PullTags(userID, since)
			if err != nil {
				zap.L().Error("Failed to pull tags", zap.Error(err))
				continue
			}
			resp.Tags = tags
		case "habits":
			habits, err := s.syncRepo.PullHabits(userID, since)
			if err != nil {
				zap.L().Error("Failed to pull habits", zap.Error(err))
				continue
			}
			resp.Habits = habits
		case "habit_logs":
			logs, err := s.syncRepo.PullHabitLogs(userID, since)
			if err != nil {
				zap.L().Error("Failed to pull habit logs", zap.Error(err))
				continue
			}
			resp.HabitLogs = logs
		}
	}

	// Record sync
	s.syncRepo.RecordSync(&model.SyncRecord{
		UserID:      userID,
		DeviceID:    req.DeviceID,
		SyncType:    "pull",
		RecordCount: len(resp.Tasks) + len(resp.Tags) + len(resp.Habits) + len(resp.HabitLogs),
		Status:      "success",
	})

	return resp, nil
}

// GetStatus returns sync status for a user
func (s *SyncService) GetStatus(userID uint, deviceID string) (*model.SyncStatusResponse, error) {
	lastSync, _ := s.syncRepo.GetLastSyncTime(userID, deviceID)

	taskCount, _ := s.syncRepo.CountTasks(userID)
	tagCount, _ := s.syncRepo.CountTags(userID)
	habitCount, _ := s.syncRepo.CountHabits(userID)
	logCount, _ := s.syncRepo.CountHabitLogs(userID)

	return &model.SyncStatusResponse{
		LastSyncTime: lastSync,
		DeviceID:     deviceID,
		TaskCount:    taskCount,
		TagCount:     tagCount,
		HabitCount:   habitCount,
		LogCount:     logCount,
	}, nil
}

// Push pushes local changes from client to server
func (s *SyncService) Push(userID uint, req *model.SyncPushRequest) (*model.SyncPushResponse, error) {
	resp := &model.SyncPushResponse{
		Success:  true,
		SyncedAt: time.Now(),
	}
	var conflicts []model.SyncConflict

	// Handle tasks
	for i := range req.Tasks {
		st := &req.Tasks[i]
		var existing model.Task
		err := s.db.Where("user_id = ? AND id = ?", userID, st.ID).First(&existing).Error
		if err != nil {
			// New task - create
			task := &model.Task{
				UserID:      userID,
				Title:       st.Title,
				Description: st.Description,
				Priority:    st.Priority,
				Category:    st.Category,
				Completed:   st.Completed,
				DeviceID:    req.DeviceID,
				SyncedAt:    time.Now(),
			}
			if st.DueTime != "" {
				if t, err := time.Parse(time.RFC3339, st.DueTime); err == nil {
					task.DueDate = &t
				}
			}
			if err := s.db.Create(task).Error; err != nil {
				zap.L().Error("Failed to create task in push", zap.Error(err))
				continue
			}
			resp.TasksCreated++
		} else {
			// Update existing
			existing.Title = st.Title
			existing.Description = st.Description
			existing.Priority = st.Priority
			existing.Category = st.Category
			existing.Completed = st.Completed
			existing.DeviceID = req.DeviceID
			existing.SyncedAt = time.Now()
			if st.DueTime != "" {
				if t, err := time.Parse(time.RFC3339, st.DueTime); err == nil {
					existing.DueDate = &t
				}
			}
			if err := s.db.Save(&existing).Error; err != nil {
				zap.L().Error("Failed to update task in push", zap.Error(err))
				continue
			}
			resp.TasksUpdated++
		}
	}

	// Handle tags
	for i := range req.Tags {
		sg := &req.Tags[i]
		var existing model.Tag
		err := s.db.Where("user_id = ? AND id = ?", userID, sg.ID).First(&existing).Error
		if err != nil {
			tag := &model.Tag{
				UserID: userID,
				Name:   sg.Name,
				Color:  sg.Color,
			}
			if err := s.db.Create(tag).Error; err != nil {
				zap.L().Error("Failed to create tag in push", zap.Error(err))
				continue
			}
			resp.TagsCreated++
		} else {
			existing.Name = sg.Name
			existing.Color = sg.Color
			if err := s.db.Save(&existing).Error; err != nil {
				zap.L().Error("Failed to update tag in push", zap.Error(err))
				continue
			}
			resp.TagsUpdated++
		}
	}

	// Handle habits
	for i := range req.Habits {
		sh := &req.Habits[i]
		var existing model.Habit
		err := s.db.Where("user_id = ? AND id = ?", userID, sh.ID).First(&existing).Error
		if err != nil {
			habit := &model.Habit{
				UserID:      userID,
				Title:       sh.Name,
				TriggerType: sh.TriggerType,
				DeviceID:    req.DeviceID,
				SyncedAt:    time.Now(),
			}
			if sh.IntervalMinutes > 0 {
				im := sh.IntervalMinutes
				habit.IntervalMinutes = &im
			}
			if sh.FixedTime != "" {
				habit.FixedTime = sh.FixedTime
			}
			if err := s.db.Create(habit).Error; err != nil {
				zap.L().Error("Failed to create habit in push", zap.Error(err))
				continue
			}
			resp.HabitsCreated++
		} else {
			existing.Title = sh.Name
			existing.TriggerType = sh.TriggerType
			existing.DeviceID = req.DeviceID
			existing.SyncedAt = time.Now()
			if err := s.db.Save(&existing).Error; err != nil {
				zap.L().Error("Failed to update habit in push", zap.Error(err))
				continue
			}
			resp.HabitsUpdated++
		}
	}

	// Handle habit logs
	for i := range req.HabitLogs {
		sl := &req.HabitLogs[i]
		var existing model.HabitLog
		err := s.db.Where("user_id = ? AND id = ?", userID, sl.ID).First(&existing).Error
		if err != nil {
			completedAt := time.Now()
			if sl.CompletedAt != "" {
				if t, err := time.Parse(time.RFC3339, sl.CompletedAt); err == nil {
					completedAt = t
				}
			}
			log := &model.HabitLog{
				UserID:      userID,
				HabitID:     fmt.Sprintf("%d", sl.HabitID),
				Count:       sl.Count,
				CompletedAt: completedAt,
				DeviceID:    req.DeviceID,
			}
			if err := s.db.Create(log).Error; err != nil {
				zap.L().Error("Failed to create habit log in push", zap.Error(err))
				continue
			}
			resp.LogsCreated++
		} else {
			existing.Count = sl.Count
			if err := s.db.Save(&existing).Error; err != nil {
				zap.L().Error("Failed to update habit log in push", zap.Error(err))
				continue
			}
			resp.LogsUpdated++
		}
	}

	resp.Conflicts = conflicts

	// Record sync
	s.syncRepo.RecordSync(&model.SyncRecord{
		UserID:      userID,
		DeviceID:    req.DeviceID,
		SyncType:    "push",
		RecordCount: resp.TasksCreated + resp.TasksUpdated + resp.TagsCreated + resp.TagsUpdated + resp.HabitsCreated + resp.HabitsUpdated + resp.LogsCreated + resp.LogsUpdated,
		Status:      "success",
	})

	return resp, nil
}
