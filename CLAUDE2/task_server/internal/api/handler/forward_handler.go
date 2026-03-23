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

type ForwardHandler struct {
	forwardService *service.ForwardService
	userService    *service.UserService
}

func NewForwardHandler(forwardService *service.ForwardService, userService *service.UserService) *ForwardHandler {
	return &ForwardHandler{
		forwardService: forwardService,
		userService:    userService,
	}
}

// ForwardTask 转发任务
// @Summary 转发任务
// @Description 将任务转发给其他用户
// @Tags forward
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Param request body model.TaskForwardRequest true "转发请求"
// @Success 200 {object} model.TaskForwardResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id}/forward [post]
func (h *ForwardHandler) ForwardTask(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	taskID, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid task id"})
		return
	}

	var req model.TaskForwardRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid forward request", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
		return
	}

	response, err := h.forwardService.ForwardTask(c.Request.Context(), uint(taskID), &req, userID.(uint))
	if err != nil {
		logger.Warn("Failed to forward task", zap.String("error", err.Error()))

		code := 1
		message := err.Error()

		switch err {
		case service.ErrTaskNotFound:
			c.JSON(http.StatusNotFound, gin.H{"code": code, "message": "任务不存在"})
			return
		case service.ErrUserNotFound:
			c.JSON(http.StatusNotFound, gin.H{"code": code, "message": "用户不存在"})
			return
		case service.ErrNoPermission:
			c.JSON(http.StatusForbidden, gin.H{"code": code, "message": "无操作权限"})
			return
		case service.ErrForwardToSelf:
			c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "不能转发给自己"})
			return
		case service.ErrAlreadyForwarded:
			c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "该任务已转发给此用户"})
			return
		case service.ErrCircularForward:
			c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "不能产生循环转发"})
			return
		case service.ErrExceedLimit:
			c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "超过转发人数限制"})
			return
		case service.ErrInvalidDeadline:
			c.JSON(http.StatusBadRequest, gin.H{"code": code, "message": "截止时间无效"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"code": code, "message": message})
		return
	}

	logger.Info("Task forwarded", zap.Uint32("task_id", uint32(taskID)), zap.Int("count", len(response.Forwards)))
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}

// RevokeForward 撤回转发
// @Summary 撤回转发
// @Description 撤回任务转发
// @Tags forward
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param id path int true "转发记录 ID"
// @Param request body model.RevokeForwardRequest true "撤回请求"
// @Success 200 {object} map[string]string
// @Failure 400 {object} map[string]string
// @Router /api/v1/forwards/{id}/revoke [post]
func (h *ForwardHandler) RevokeForward(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	forwardID, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid forward id"})
		return
	}

	var req model.RevokeForwardRequest
	c.ShouldBindJSON(&req) // Reason is optional

	err = h.forwardService.RevokeForward(c.Request.Context(), uint(forwardID), req.Reason, userID.(uint))
	if err != nil {
		logger.Warn("Failed to revoke forward", zap.String("error", err.Error()))

		switch err {
		case service.ErrTaskNotFound:
			c.JSON(http.StatusNotFound, gin.H{"code": 1, "message": "转发记录不存在"})
			return
		case service.ErrNoPermission:
			c.JSON(http.StatusForbidden, gin.H{"code": 1, "message": "只有转发者可以撤回"})
			return
		case service.ErrForwardRevoked:
			c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "转发已撤回"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
		return
	}

	logger.Info("Forward revoked", zap.Uint32("forward_id", uint32(forwardID)))
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success"})
}

// GetTaskForwards 获取任务转发列表
// @Summary 获取任务转发列表
// @Description 获取指定任务的所有转发记录
// @Tags forward
// @Produce json
// @Security BearerAuth
// @Param id path int true "任务 ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Router /api/v1/tasks/{id}/forwards [get]
func (h *ForwardHandler) GetTaskForwards(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	idParam := c.Param("id")
	taskID, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": "invalid task id"})
		return
	}

	forwards, err := h.forwardService.GetTaskForwards(c.Request.Context(), uint(taskID), userID.(uint))
	if err != nil {
		logger.Error("Failed to get task forwards", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to get forwards"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": gin.H{
		"forwards": forwards,
		"total":    len(forwards),
	}})
}

// GetReceivedForwards 获取接收到的转发列表
// @Summary 获取接收到的转发列表
// @Description 获取当前用户接收到的所有任务转发
// @Tags forward
// @Produce json
// @Security BearerAuth
// @Param page query int false "页码" default(1)
// @Param page_size query int false "每页数量" default(10)
// @Success 200 {object} model.ReceivedForwardListResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/forwards/received [get]
func (h *ForwardHandler) GetReceivedForwards(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	var req struct {
		Page     int `form:"page,default=1"`
		PageSize int `form:"page_size,default=10"`
	}
	if err := c.ShouldBindQuery(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}

	response, err := h.forwardService.GetReceivedForwards(c.Request.Context(), userID.(uint), req.Page, req.PageSize)
	if err != nil {
		logger.Error("Failed to get received forwards", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to get forwards"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}
