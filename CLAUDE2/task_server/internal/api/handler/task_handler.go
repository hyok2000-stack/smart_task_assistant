package handler

import (
	"net/http"
	"strconv"
	"task_server/internal/model"
	"task_server/internal/service"
	"task_server/pkg/logger"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type TaskHandler struct {
	taskService *service.TaskService
}

func NewTaskHandler(taskService *service.TaskService) *TaskHandler {
	return &TaskHandler{taskService: taskService}
}

// CreateTask 创建任务
// @Summary 创建任务
// @Description 创建新任务
// @Tags task
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body model.TaskRequest true "任务信息"
// @Success 200 {object} model.Task
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks [post]
func (h *TaskHandler) CreateTask(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid task request", zap.String("error", err.Error()))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	task, err := h.taskService.Create(userID.(uint), &req)
	if err != nil {
		logger.Error("Failed to create task", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create task"})
		return
	}

	logger.Info("Task created", zap.Uint32("task_id", uint32(task.ID)), zap.Uint32("user_id", uint32(userID.(uint))))
	c.JSON(http.StatusOK, task)
}

// GetTask 获取任务详情
// @Summary 获取任务详情
// @Description 根据 ID 获取任务详情
// @Tags task
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Success 200 {object} model.Task
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id} [get]
func (h *TaskHandler) GetTask(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	id, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	task, err := h.taskService.GetByID(uint(id), userID.(uint))
	if err != nil {
		logger.Error("Failed to get task", zap.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": "task not found"})
		return
	}

	c.JSON(http.StatusOK, task)
}

// GetTaskList 获取任务列表
// @Summary 获取任务列表
// @Description 获取当前用户的任务列表
// @Tags task
// @Produce json
// @Security BearerAuth
// @Param page query int false "页码" default(1)
// @Param page_size query int false "每页数量" default(10)
// @Param completed query bool false "完成状态"
// @Param priority query int false "优先级"
// @Param category query string false "分类"
// @Param keyword query string false "关键词"
// @Success 200 {object} model.TaskListResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks [get]
func (h *TaskHandler) GetTaskList(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.TaskListRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		logger.Warn("Invalid task list request", zap.String("error", err.Error()))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.taskService.GetList(userID.(uint), &req)
	if err != nil {
		logger.Error("Failed to get task list", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get task list"})
		return
	}

	c.JSON(http.StatusOK, response)
}

// UpdateTask 更新任务
// @Summary 更新任务
// @Description 更新任务信息
// @Tags task
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Param request body model.TaskRequest true "任务信息"
// @Success 200 {object} model.Task
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id} [put]
func (h *TaskHandler) UpdateTask(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	id, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	var req model.TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid task update request", zap.String("error", err.Error()))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	task, err := h.taskService.Update(uint(id), userID.(uint), &req)
	if err != nil {
		logger.Error("Failed to update task", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update task"})
		return
	}

	logger.Info("Task updated", zap.Uint32("task_id", uint32(task.ID)))
	c.JSON(http.StatusOK, task)
}

// DeleteTask 删除任务
// @Summary 删除任务
// @Description 删除任务
// @Tags task
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id} [delete]
func (h *TaskHandler) DeleteTask(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	id, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	err = h.taskService.Delete(uint(id), userID.(uint))
	if err != nil {
		logger.Error("Failed to delete task", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete task"})
		return
	}

	logger.Info("Task deleted", zap.Uint32("task_id", uint32(id)))
	c.JSON(http.StatusOK, gin.H{"message": "task deleted successfully"})
}

// ToggleComplete 切换任务完成状态
// @Summary 切换任务完成状态
// @Description 切换任务的完成状态
// @Tags task
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Success 200 {object} model.Task
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id}/toggle [patch]
func (h *TaskHandler) ToggleComplete(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	id, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid task id"})
		return
	}

	task, err := h.taskService.ToggleComplete(uint(id), userID.(uint))
	if err != nil {
		logger.Error("Failed to toggle task complete", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to toggle task complete"})
		return
	}

	logger.Info("Task completed toggled", zap.Uint32("task_id", uint32(task.ID)), zap.Bool("completed", task.Completed))
	c.JSON(http.StatusOK, task)
}

// GetTaskStats 获取任务统计
// @Summary 获取任务统计
// @Description 获取当前用户的任务统计信息
// @Tags task
// @Produce json
// @Security BearerAuth
// @Success 200 {object} model.TaskStats
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/stats [get]
func (h *TaskHandler) GetTaskStats(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	stats, err := h.taskService.GetStats(userID.(uint))
	if err != nil {
		logger.Error("Failed to get task stats", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get task stats"})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetAllTasks 管理员获取所有任务
// @Summary 管理员获取所有任务
// @Description 获取所有用户的任务列表（仅管理员）
// @Tags task
// @Produce json
// @Security BearerAuth
// @Param page query int false "页码" default(1)
// @Param page_size query int false "每页数量" default(10)
// @Success 200 {object} model.TaskListResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/all [get]
func (h *TaskHandler) GetAllTasks(c *gin.Context) {
	userRole, exists := c.Get("user_role")
	if !exists || userRole != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin only"})
		return
	}

	var req struct {
		Page     int `form:"page,default=1"`
		PageSize int `form:"page_size,default=10"`
	}
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.taskService.GetAllTasks(req.Page, req.PageSize)
	if err != nil {
		logger.Error("Failed to get all tasks", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get all tasks"})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetAllStats 管理员获取所有任务统计
// @Summary 管理员获取所有任务统计
// @Description 获取所有用户的任务统计信息（仅管理员）
// @Tags task
// @Produce json
// @Security BearerAuth
// @Success 200 {object} model.TaskStats
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/all/stats [get]
func (h *TaskHandler) GetAllStats(c *gin.Context) {
	userRole, exists := c.Get("user_role")
	if !exists || userRole != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin only"})
		return
	}

	stats, err := h.taskService.GetAllStats()
	if err != nil {
		logger.Error("Failed to get all task stats", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get all task stats"})
		return
	}

	c.JSON(http.StatusOK, stats)
}
