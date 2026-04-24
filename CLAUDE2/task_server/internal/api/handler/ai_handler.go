package handler

import (
	"net/http"
	"task_server/internal/service"

	"github.com/gin-gonic/gin"
)

type AIHandler struct {
	aiService *service.AIService
}

func NewAIHandler(aiService *service.AIService) *AIHandler {
	return &AIHandler{aiService: aiService}
}

type aiChatRequest struct {
	Message string `json:"message" binding:"required"`
}

func (h *AIHandler) Chat(c *gin.Context) {
	var req aiChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}

	messages := []service.ChatMessage{
		{Role: "user", Content: req.Message},
	}

	resp, err := h.aiService.Chat(messages)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "data": resp})
}
