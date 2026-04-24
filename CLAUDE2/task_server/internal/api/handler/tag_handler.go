package handler

import (
	"net/http"
	"strconv"
	"task_server/internal/service"

	"github.com/gin-gonic/gin"
)

type TagHandler struct {
	tagService *service.TagService
}

func NewTagHandler(tagService *service.TagService) *TagHandler {
	return &TagHandler{tagService: tagService}
}

func (h *TagHandler) List(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	tags, err := h.tagService.List(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": tags})
}

type createTagRequest struct {
	LocalID   string `json:"local_id"`
	Name      string `json:"name" binding:"required"`
	Color     string `json:"color"`
	Icon      string `json:"icon"`
	SortOrder int    `json:"sort_order"`
	IsDefault bool   `json:"is_default"`
}

func (h *TagHandler) Create(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	var req createTagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	tag, err := h.tagService.CreateWithFields(userID, req.LocalID, req.Name, req.Color, req.Icon, req.SortOrder, req.IsDefault)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": tag})
}

type updateTagRequest struct {
	LocalID   string `json:"local_id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	Icon      string `json:"icon"`
	SortOrder *int   `json:"sort_order"`
	IsDefault *bool  `json:"is_default"`
}

func (h *TagHandler) Update(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	var req updateTagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	tag, err := h.tagService.UpdateWithFields(uint(id), userID, req.LocalID, req.Name, req.Color, req.Icon, req.SortOrder, req.IsDefault)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "data": tag})
}

func (h *TagHandler) Delete(c *gin.Context) {
	userID, ok := getUserID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"code": 1, "message": "unauthorized"})
		return
	}
	id, _ := strconv.ParseUint(c.Param("id"), 10, 32)
	if err := h.tagService.Delete(uint(id), userID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 1, "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "删除成功"})
}
