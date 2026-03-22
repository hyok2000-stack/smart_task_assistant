package router

import (
	"task_server/internal/api/handler"
	"task_server/internal/api/middleware"

	"github.com/gin-gonic/gin"
)

// SetupRouter 设置路由
func SetupRouter(userHandler *handler.UserHandler, taskHandler *handler.TaskHandler) *gin.Engine {
	router := gin.New()

	// 全局中间件
	router.Use(middleware.Recovery())
	router.Use(middleware.Logger())
	router.Use(middleware.CORS())
	router.Use(middleware.ErrorHandler())

	// 静态文件服务 - 后台管理页面
	router.Static("/admin", "./static")

	// 根路径 - 重定向到管理页面
	router.GET("/", func(c *gin.Context) {
		c.Redirect(302, "/admin")
	})

	// 欢迎页面
	router.GET("/welcome", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "欢迎使用 Task Server API",
			"version": "1.0.0",
			"endpoints": gin.H{
				"health":       "/health",
				"api_base":     "/api/v1",
				"register":     "/api/v1/auth/register",
				"login":        "/api/v1/auth/login",
				"tasks":        "/api/v1/tasks (需要认证)",
				"user_profile": "/api/v1/user/profile (需要认证)",
			},
			"documentation": "请参考 API 文档了解详细信息",
		})
	})

	// 健康检查
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"message": "Task Server is running",
		})
	})

	// API v1 路由组
	v1 := router.Group("/api/v1")
	{
		// 认证路由（无需 JWT）
		auth := v1.Group("/auth")
		{
			auth.POST("/register", userHandler.Register)
			auth.POST("/login", userHandler.Login)
		}

		// 用户路由（需要 JWT）
		user := v1.Group("/user")
		user.Use(middleware.JWTAuth())
		{
			user.GET("/profile", userHandler.GetProfile)
			user.PUT("/profile", userHandler.UpdateProfile)
		}

		// 任务路由（需要 JWT）
		tasks := v1.Group("/tasks")
		tasks.Use(middleware.JWTAuth())
		{
			tasks.POST("", taskHandler.CreateTask)
			tasks.GET("", taskHandler.GetTaskList)
			tasks.GET("/stats", taskHandler.GetTaskStats)
			tasks.GET("/:id", taskHandler.GetTask)
			tasks.PUT("/:id", taskHandler.UpdateTask)
			tasks.DELETE("/:id", taskHandler.DeleteTask)
			tasks.PATCH("/:id/toggle", taskHandler.ToggleComplete)
		}
	}

	return router
}
