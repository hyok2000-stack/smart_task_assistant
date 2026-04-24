package handler

import (
	"net/http"
	"strconv"
	"task_server/internal/service"

	"github.com/gin-gonic/gin"
)

type DeviceHandler struct {
	deviceService *service.DeviceService
}

func NewDeviceHandler(deviceService *service.DeviceService) *DeviceHandler {
	return &DeviceHandler{deviceService: deviceService}
}

func (h *DeviceHandler) List(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	devices, err := h.deviceService.List(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": devices})
}

func (h *DeviceHandler) Register(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	var req service.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	device, err := h.deviceService.Register(userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": device})
}

func (h *DeviceHandler) Delete(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	if err := h.deviceService.Delete(uint(id), userID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "删除成功"})
}

type updatePushTokenRequest struct {
	PushToken string `json:"push_token" binding:"required"`
}

func (h *DeviceHandler) UpdatePushToken(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var req updatePushTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	if err := h.deviceService.UpdatePushToken(uint(id), userID, req.PushToken); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "更新成功"})
}
