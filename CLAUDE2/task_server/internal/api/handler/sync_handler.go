package handler

import (
	"net/http"
	"task_server/internal/model"
	"task_server/internal/service"

	"github.com/gin-gonic/gin"
)

type SyncHandler struct {
	syncService *service.SyncService
}

func NewSyncHandler(syncService *service.SyncService) *SyncHandler {
	return &SyncHandler{syncService: syncService}
}

// Pull pulls data from server
func (h *SyncHandler) Pull(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	var req model.SyncPullRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}

	resp, err := h.syncService.Pull(userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "data": resp})
}

// GetStatus returns sync status
func (h *SyncHandler) GetStatus(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	deviceID := c.Query("device_id")
	resp, err := h.syncService.GetStatus(userID, deviceID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "data": resp})
}

// Push pushes local changes from client to server
func (h *SyncHandler) Push(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}

	var req model.SyncPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}

	resp, err := h.syncService.Push(userID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "data": resp})
}
