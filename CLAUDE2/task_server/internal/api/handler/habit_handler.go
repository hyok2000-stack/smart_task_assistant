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

// HabitHandler 习惯处理器
type HabitHandler struct {
	habitService *service.HabitService
	logService   *service.HabitLogService
	presetHabits *service.PresetHabitsService
	repo         repository.HabitRepository
}

// NewHabitHandler 创建习惯处理器
func NewHabitHandler(
	habitService *service.HabitService,
	logService *service.HabitLogService,
	presetHabits *service.PresetHabitsService,
	repo repository.HabitRepository,
) *HabitHandler {
	return &HabitHandler{
		habitService: habitService,
		logService:   logService,
		presetHabits: presetHabits,
		repo:         repo,
	}
}

// Create 创建习惯
func (h *HabitHandler) Create(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.CreateHabitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	habit, err := h.habitService.Create(userID, &req)
	if err != nil {
		logger.Error("Failed to create habit", zap.Error(err))
		handleError(c, err)
		return
	}

	c.JSON(http.StatusCreated, habit)
}

// GetByID 根据数据库 ID 获取习惯
func (h *HabitHandler) GetByID(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	habit, err := h.habitService.GetByID(uint(id), userID)
	if err != nil {
		handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, habit)
}

// GetByHabitID 根据 HabitID 获取习惯
func (h *HabitHandler) GetByHabitID(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	habit, err := h.habitService.GetByHabitID(habitID, userID)
	if err != nil {
		handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, habit)
}

// List 列出用户的习惯
func (h *HabitHandler) List(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.ListHabitsRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.habitService.List(userID, &req)
	if err != nil {
		logger.Error("Failed to list habits", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

// Update 更新习惯
func (h *HabitHandler) Update(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var req model.UpdateHabitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	habit, err := h.habitService.Update(uint(id), userID, &req)
	if err != nil {
		handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, habit)
}

// Delete 删除习惯
func (h *HabitHandler) Delete(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseUint(idStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	if err := h.habitService.Delete(uint(id), userID); err != nil {
		handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "habit deleted"})
}

// ToggleEnabled 切换启用状态
func (h *HabitHandler) ToggleEnabled(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	habitID := c.Param("habit_id")

	if err := h.habitService.ToggleEnabled(habitID, userID); err != nil {
		handleError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "habit enabled status toggled"})
}

// Sync 从设备同步习惯
func (h *HabitHandler) Sync(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req model.SyncHabitsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 转换 []model.Habit 为 []*model.Habit
	habitPtrs := make([]*model.Habit, len(req.Habits))
	for i := range req.Habits {
		habitPtrs[i] = &req.Habits[i]
	}

	if err := h.habitService.SyncFromDevice(userID, req.DeviceID, habitPtrs); err != nil {
		logger.Error("Failed to sync habits", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 获取同步后的习惯列表
	habits, err := h.repo.FindByDeviceID(req.DeviceID, userID)
	if err != nil {
		c.JSON(http.StatusOK, model.SyncHabitsResponse{
			SyncedCount: len(req.Habits),
			Habits:      convertHabitsToSlice(habits),
		})
		return
	}

	c.JSON(http.StatusOK, model.SyncHabitsResponse{
		SyncedCount: len(req.Habits),
		Habits:      convertHabitsToSlice(habits),
	})
}

// InitializeDefaults 初始化默认习惯
func (h *HabitHandler) InitializeDefaults(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	deviceID := c.Query("device_id")
	if deviceID == "" {
		deviceID = "default"
	}

	if err := h.presetHabits.InitializeDefaults(userID, deviceID); err != nil {
		logger.Error("Failed to initialize default habits", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 获取初始化后的习惯列表
	habits, err := h.repo.FindByUserID(userID)
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"message": "default habits initialized",
			"count":   4,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "default habits initialized",
		"count":   len(habits),
		"habits":  convertHabitsToSlice(habits),
	})
}

// HasDefaults 检查是否已初始化默认习惯
func (h *HabitHandler) HasDefaults(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	hasDefaults, err := h.presetHabits.HasDefaultsInitialized(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"has_defaults": hasDefaults,
	})
}

// GetTodayWithStats 获取今日习惯及统计
func (h *HabitHandler) GetTodayWithStats(c *gin.Context) {
	userID, _ := getUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// 获取所有习惯
	habits, err := h.repo.FindByUserID(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 获取今日统计
	stats, err := h.logService.GetTodayStatsForAll(userID)
	if err != nil {
		logger.Error("Failed to get today stats", zap.Error(err))
	}

	// 合并习惯和统计
	type HabitWithStats struct {
		model.Habit
		Stats *model.HabitStats `json:"stats,omitempty"`
	}

	result := make([]HabitWithStats, len(habits))
	for i, habit := range habits {
		result[i] = HabitWithStats{
			Habit: *habit,
			Stats: stats[habit.HabitID],
		}
	}

	c.JSON(http.StatusOK, gin.H{"habits": result})
}

// Helper function to convert []*Habit to []Habit
func convertHabitsToSlice(habits []*model.Habit) []model.Habit {
	result := make([]model.Habit, len(habits))
	for i, h := range habits {
		result[i] = *h
	}
	return result
}

// handleError 处理错误并返回适当的 HTTP 状态码
func handleError(c *gin.Context, err error) {
	switch err {
	case repository.ErrHabitNotFound:
		c.JSON(http.StatusNotFound, gin.H{"error": "habit not found"})
	case repository.ErrHabitAlreadyExists:
		c.JSON(http.StatusConflict, gin.H{"error": "habit with this ID already exists"})
	case service.ErrInvalidTriggerType, service.ErrMissingInterval,
		service.ErrMissingFixedTime, service.ErrInvalidTarget,
		service.ErrInvalidVoiceSpeed, service.ErrInvalidScheduleType:
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
	default:
		logger.Error("Internal server error", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal server error"})
	}
}
