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

type UserHandler struct {
	userService *service.UserService
}

func NewUserHandler(userService *service.UserService) *UserHandler {
	return &UserHandler{userService: userService}
}

// Register 用户注册
// @Summary 用户注册
// @Description 注册新用户
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.RegisterRequest true "注册信息"
// @Success 200 {object} model.User
// @Failure 400 {object} map[string]string
// @Router /api/v1/auth/register [post]
func (h *UserHandler) Register(c *gin.Context) {
	var req model.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid register request", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{
			"code":    1,
			"message": err.Error(),
		})
		return
	}

	user, err := h.userService.Register(&req)
	if err != nil {
		logger.Warn("Registration failed", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{
			"code":    1,
			"message": err.Error(),
		})
		return
	}

	logger.Info("User registered successfully", zap.Uint32("user_id", uint32(user.ID)))
	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "success",
		"data":    user,
	})
}

// Login 用户登录
// @Summary 用户登录
// @Description 用户登录获取 token
// @Tags auth
// @Accept json
// @Produce json
// @Param request body model.LoginRequest true "登录信息"
// @Success 200 {object} model.LoginResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/auth/login [post]
func (h *UserHandler) Login(c *gin.Context) {
	var req model.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Warn("Invalid login request", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{
			"code":    1,
			"message": err.Error(),
		})
		return
	}

	response, err := h.userService.Login(&req)
	if err != nil {
		logger.Warn("Login failed", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{
			"code":    1,
			"message": err.Error(),
		})
		return
	}

	logger.Info("User logged in successfully", zap.String("username", req.Username))
	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "success",
		"data":    response,
	})
}

// GetProfile 获取用户信息
// @Summary 获取用户信息
// @Description 获取当前登录用户的信息
// @Tags user
// @Produce json
// @Security BearerAuth
// @Success 200 {object} model.User
// @Failure 401 {object} map[string]string
// @Router /api/v1/user/profile [get]
func (h *UserHandler) GetProfile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	user, err := h.userService.GetByID(userID.(uint))
	if err != nil {
		logger.Error("Failed to get user profile", zap.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// UpdateProfile 更新用户信息
// @Summary 更新用户信息
// @Description 更新当前登录用户的信息
// @Tags user
// @Accept json
// @Produce json
// @Security BearerAuth
// @Param request body model.User true "用户信息"
// @Success 200 {object} model.User
// @Failure 400 {object} map[string]string
// @Router /api/v1/user/profile [put]
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var user model.User
	if err := c.ShouldBindJSON(&user); err != nil {
		logger.Warn("Invalid update request", zap.String("error", err.Error()))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user.ID = userID.(uint)
	err := h.userService.Update(&user)
	if err != nil {
		logger.Error("Failed to update user profile", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update profile"})
		return
	}

	logger.Info("User profile updated", zap.Uint32("user_id", uint32(user.ID)))
	c.JSON(http.StatusOK, user)
}

// GetUserByID 根据 ID 获取用户（管理员功能）
// @Summary 根据 ID 获取用户
// @Description 根据 ID 获取用户信息
// @Tags user
// @Produce json
// @Security BearerAuth
// @Param id path int true "用户 ID"
// @Success 200 {object} model.User
// @Failure 400 {object} map[string]string
// @Router /api/v1/user/{id} [get]
func (h *UserHandler) GetUserByID(c *gin.Context) {
	idParam := c.Param("id")
	id, err := strconv.ParseUint(idParam, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	user, err := h.userService.GetByID(uint(id))
	if err != nil {
		logger.Error("Failed to get user", zap.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// SearchUsers 搜索用户
// @Summary 搜索用户
// @Description 根据关键词搜索用户
// @Tags user
// @Produce json
// @Security BearerAuth
// @Param keyword query string true "搜索关键词"
// @Param limit query int false "返回数量限制"
// @Success 200 {object} model.SearchUsersResponse
// @Failure 400 {object} map[string]string
// @Router /api/v1/user/search [get]
func (h *UserHandler) SearchUsers(c *gin.Context) {
	var req model.SearchUsersRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		logger.Warn("Invalid search users request", zap.String("error", err.Error()))
		c.JSON(http.StatusOK, gin.H{"code": 1, "message": err.Error()})
		return
	}

	response, err := h.userService.SearchUsers(req.Keyword, req.Limit)
	if err != nil {
		logger.Error("Failed to search users", zap.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": "failed to search users"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success", "data": response})
}
