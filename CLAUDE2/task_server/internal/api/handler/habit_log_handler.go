package handler

import (
	"net/http"
	"strconv"

	"task_server/internal/model"
	"task_server/internal/repository"
	"task_server/internal/service"
	"task_server/pkg/logger"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// HabitLogHandler 习惯日志处理器
type HabitLogHandler struct {
	logService *service.HabitLogService
}

// NewHabitLogHandler 创建习惯日志处理器
func NewHabitLogHandler(logService *service.HabitLogService) *HabitLogHandler {
	return &HabitLogHandler{
		logService: logService,
	}
}

// LogCompletion 记录完成
func (h *HabitLogHandler) LogCompletion(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	var req model.LogCompletionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	log, err := h.logService.LogCompletionWithDeviceID(userID, habitID, req.Count, req.Status, req.DeviceID)
	if err != nil {
		logger.Error("Failed to log completion", zap.Error(err))
		handleLogError(c, err)
		return
	}

	c.JSON(http.StatusCreated, log)
}

// List 列出日志
func (h *HabitLogHandler) List(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	var req model.ListHabitLogsRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.logService.List(habitID, userID, &req)
	if err != nil {
		handleLogError(c, err)
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetStats 获取统计信息
func (h *HabitLogHandler) GetStats(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	stats, err := h.logService.GetStats(habitID, userID)
	if err != nil {
		handleLogError(c, err)
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetHistory 获取历史记录
func (h *HabitLogHandler) GetHistory(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	// 获取天数参数，默认 30 天
	daysStr := c.DefaultQuery("days", "30")
	days, err := strconv.Atoi(daysStr)
	if err != nil || days < 1 {
		days = 30
	}
	if days > 365 {
		days = 365 // 最多 365 天
	}

	response, err := h.logService.GetHistory(habitID, userID, days)
	if err != nil {
		logger.Error("Failed to get habit history", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// GetProgress 获取进度
func (h *HabitLogHandler) GetProgress(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	// 获取目标数量
	targetStr := c.DefaultQuery("target", "8")
	target, _ := strconv.Atoi(targetStr)

	percentage, err := h.logService.GetProgressPercentage(habitID, userID, target)
	if err != nil {
		handleLogError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"percentage": percentage,
	})
}

// GetTodayProgress 获取今日进度
func (h *HabitLogHandler) GetTodayProgress(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	progress, err := h.logService.GetTodayProgress(habitID, userID)
	if err != nil {
		handleLogError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"today_progress": progress,
	})
}

// GetStreak 获取连续天数
func (h *HabitLogHandler) GetStreak(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	streak, err := h.logService.CalculateStreak(habitID, userID)
	if err != nil {
		logger.Error("Failed to calculate streak", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"streak_days": streak,
	})
}

// handleLogError 处理日志相关错误
func handleLogError(c *gin.Context, err error) {
	switch err {
	case repository.ErrHabitNotFound:
		c.JSON(http.StatusNotFound, gin.H{"error": "habit not found"})
	case repository.ErrHabitLogNotFound:
		c.JSON(http.StatusNotFound, gin.H{"error": "habit log not found"})
	default:
		logger.Error("Internal server error", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
	}
}
