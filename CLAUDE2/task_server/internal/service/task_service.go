package service

import (
	"context"
	"errors"
	"fmt"
	"task_server/internal/model"
	"task_server/internal/repository"
	"time"
)

type TaskService struct {
	taskRepo    *repository.TaskRepository
	forwardRepo *repository.ForwardRepository
	forwardSvc  *ForwardService
}

func NewTaskService(taskRepo *repository.TaskRepository) *TaskService {
	return &TaskService{taskRepo: taskRepo}
}

func NewTaskServiceWithForward(taskRepo *repository.TaskRepository, forwardRepo *repository.ForwardRepository, forwardSvc *ForwardService) *TaskService {
	return &TaskService{
		taskRepo:    taskRepo,
		forwardRepo: forwardRepo,
		forwardSvc:  forwardSvc,
	}
}

// Create 创建任务
func (s *TaskService) Create(userID uint, req *model.TaskRequest) (*model.Task, error) {
	task := &model.Task{
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		Priority:    req.Priority,
		DueDate:     req.DueDate,
		RemindAt:    req.RemindAt,
		Category:    req.Category,
		Completed:   false,
		Reminded:    false,
		SyncedAt:    time.Now(),
	}

	// 处理标签
	if len(req.Tags) > 0 {
		tags := make([]model.Tag, 0, len(req.Tags))
		for _, tagName := range req.Tags {
			tags = append(tags, model.Tag{
				UserID: userID,
				Name:   tagName,
			})
		}
		task.Tags = tags
	}

	err := s.taskRepo.Create(task)
	if err != nil {
		return nil, err
	}

	return task, nil
}

// GetByID 根据 ID 获取任务
func (s *TaskService) GetByID(id uint, userID uint) (*model.Task, error) {
	task, err := s.taskRepo.FindByID(id)
	if err != nil {
		return nil, err
	}

	// 检查任务是否属于该用户
	if task.UserID != userID {
		return nil, errors.New("unauthorized")
	}

	return task, nil
}

// GetList 获取任务列表
func (s *TaskService) GetList(userID uint, req *model.TaskListRequest) (*model.TaskListResponse, error) {
	offset := (req.Page - 1) * req.PageSize

	filters := make(map[string]interface{})
	if req.Completed != nil {
		filters["completed"] = *req.Completed
	}
	if req.Priority != nil {
		filters["priority"] = *req.Priority
	}
	if req.Category != "" {
		filters["category"] = req.Category
	}
	if req.Keyword != "" {
		filters["keyword"] = req.Keyword
	}

	tasks, total, err := s.taskRepo.FindByUserID(userID, offset, req.PageSize, filters)
	if err != nil {
		return nil, err
	}

	taskResponses := make([]model.TaskResponse, 0, len(tasks))
	for _, task := range tasks {
		taskResponses = append(taskResponses, model.TaskResponse{
			Task: task,
			Tags: task.Tags,
		})
	}

	totalPages := int(total) / req.PageSize
	if int(total)%req.PageSize > 0 {
		totalPages++
	}

	return &model.TaskListResponse{
		Tasks:      taskResponses,
		Total:      total,
		Page:       req.Page,
		PageSize:   req.PageSize,
		TotalPages: totalPages,
	}, nil
}

// Update 更新任务
func (s *TaskService) Update(id uint, userID uint, req *model.TaskRequest) (*model.Task, error) {
	task, err := s.taskRepo.FindByID(id)
	if err != nil {
		return nil, err
	}

	// 检查任务是否属于该用户
	if task.UserID != userID {
		return nil, errors.New("unauthorized")
	}

	// 更新字段
	task.Title = req.Title
	task.Description = req.Description
	task.Priority = req.Priority
	task.DueDate = req.DueDate
	task.RemindAt = req.RemindAt
	task.Category = req.Category
	task.SyncedAt = time.Now()

	// 如果标记为完成，记录完成时间
	if req.Completed != nil && *req.Completed && !task.Completed {
		now := time.Now()
		task.CompletedAt = &now
	}
	task.Completed = req.Completed != nil && *req.Completed

	err = s.taskRepo.Update(task)
	if err != nil {
		return nil, err
	}

	// Sync to forwarded tasks if this is not a forwarded task
	if !task.IsForwarded && s.forwardSvc != nil {
		go func() {
			defer func() {
				if r := recover(); r != nil {
					// Log the panic - using fmt for now since logger may not be available
					fmt.Printf("Task sync panic: %v\n", r)
				}
			}()
			s.forwardSvc.SyncTaskStatus(context.Background(), task.ID, userID)
		}()
	}

	return task, nil
}

// Delete 删除任务
func (s *TaskService) Delete(id uint, userID uint) error {
	task, err := s.taskRepo.FindByID(id)
	if err != nil {
		return err
	}

	// 检查任务是否属于该用户
	if task.UserID != userID {
		return errors.New("unauthorized")
	}

	return s.taskRepo.Delete(id)
}

// GetStats 获取任务统计
func (s *TaskService) GetStats(userID uint) (*model.TaskStats, error) {
	return s.taskRepo.GetStats(userID)
}

// ToggleComplete 切换任务完成状态
func (s *TaskService) ToggleComplete(id uint, userID uint) (*model.Task, error) {
	task, err := s.taskRepo.FindByID(id)
	if err != nil {
		return nil, err
	}

	// 检查任务是否属于该用户
	if task.UserID != userID {
		return nil, errors.New("unauthorized")
	}

	task.Completed = !task.Completed
	if task.Completed {
		now := time.Now()
		task.CompletedAt = &now
	} else {
		task.CompletedAt = nil
	}
	task.SyncedAt = time.Now()

	err = s.taskRepo.Update(task)
	if err != nil {
		return nil, err
	}

	// Sync to forwarded tasks
	if !task.IsForwarded && s.forwardSvc != nil {
		go func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("Task sync panic: %v\n", r)
				}
			}()
			s.forwardSvc.SyncTaskStatus(context.Background(), task.ID, userID)
		}()
	} else if task.IsForwarded && s.forwardSvc != nil {
		go func() {
			defer func() {
				if r := recover(); r != nil {
					fmt.Printf("Task sync panic: %v\n", r)
				}
			}()
			s.forwardSvc.SyncToParentTask(context.Background(), task.ID)
		}()
	}

	return task, nil
}
