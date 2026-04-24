package router

import (
	"task_server/internal/api/handler"
	"task_server/internal/api/middleware"

	"github.com/gin-gonic/gin"
)

// SetupRouter 设置路由
func SetupRouter(
	userHandler *handler.UserHandler,
	taskHandler *handler.TaskHandler,
	forwardHandler *handler.ForwardHandler,
	habitHandler *handler.HabitHandler,
	habitLogHandler *handler.HabitLogHandler,
	syncHandler *handler.SyncHandler,
	tagHandler *handler.TagHandler,
	deviceHandler *handler.DeviceHandler,
	aiHandler *handler.AIHandler,
) *gin.Engine {
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
				"habits":       "/api/v1/habits (需要认证)",
				"habit_logs":   "/api/v1/habits/:habit_id/logs (需要认证)",
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
			user.GET("/search", userHandler.SearchUsers)
		}

		// 用户管理路由（需要 JWT）
		users := v1.Group("/users")
		users.Use(middleware.JWTAuth())
		{
			users.GET("", userHandler.ListUsers)
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

			// 任务转发相关路由
			tasks.POST("/:id/forward", forwardHandler.ForwardTask)
			tasks.GET("/:id/forwards", forwardHandler.GetTaskForwards)
		}

		// 习惯路由（需要 JWT）
		habits := v1.Group("/habits")
		habits.Use(middleware.JWTAuth())
		{
			habits.POST("", habitHandler.Create)
			habits.GET("", habitHandler.List)
			habits.GET("/today", habitHandler.GetTodayWithStats)
			habits.GET("/has-defaults", habitHandler.HasDefaults)
			habits.POST("/initialize-defaults", habitHandler.InitializeDefaults)
			habits.POST("/sync", habitHandler.Sync)
			habits.GET("/:habit_id", habitHandler.GetByHabitID)
			habits.PUT("/:habit_id", habitHandler.Update)
			habits.DELETE("/:habit_id", habitHandler.Delete)
			habits.PATCH("/:habit_id/toggle", habitHandler.ToggleEnabled)

			// 习惯日志路由
			habits.POST("/:habit_id/logs", habitLogHandler.LogCompletion)
			habits.GET("/:habit_id/logs", habitLogHandler.List)
			habits.GET("/:habit_id/stats", habitLogHandler.GetStats)
			habits.GET("/:habit_id/history", habitLogHandler.GetHistory)
			habits.GET("/:habit_id/progress", habitLogHandler.GetProgress)
			habits.GET("/:habit_id/streak", habitLogHandler.GetStreak)
			habits.GET("/:habit_id/today-progress", habitLogHandler.GetTodayProgress)
		}

		// 转发路由（需要 JWT）
		forwards := v1.Group("/forwards")
		forwards.Use(middleware.JWTAuth())
		{
			forwards.GET("/received", forwardHandler.GetReceivedForwards)
			forwards.POST("/:id/revoke", forwardHandler.RevokeForward)
		}

		// 数据同步路由（需要 JWT）
		syncGroup := v1.Group("/sync")
		syncGroup.Use(middleware.JWTAuth())
		{
			syncGroup.POST("/pull", syncHandler.Pull)
			syncGroup.POST("/push", syncHandler.Push)
			syncGroup.GET("/status", syncHandler.GetStatus)
		}

		// 标签路由（需要 JWT）
		tagsGroup := v1.Group("/tags")
		tagsGroup.Use(middleware.JWTAuth())
		{
			tagsGroup.GET("", tagHandler.List)
			tagsGroup.POST("", tagHandler.Create)
			tagsGroup.PUT("/:id", tagHandler.Update)
			tagsGroup.DELETE("/:id", tagHandler.Delete)
		}

		// 设备路由（需要 JWT）
		devicesGroup := v1.Group("/devices")
		devicesGroup.Use(middleware.JWTAuth())
		{
			devicesGroup.GET("", deviceHandler.List)
			devicesGroup.POST("", deviceHandler.Register)
			devicesGroup.DELETE("/:id", deviceHandler.Delete)
			devicesGroup.PUT("/:id", deviceHandler.UpdatePushToken)
		}

		// AI 路由（需要 JWT）
		aiGroup := v1.Group("/ai")
		aiGroup.Use(middleware.JWTAuth())
		{
			aiGroup.POST("/chat", aiHandler.Chat)
		}

		// 管理员路由（需要 JWT + admin 角色）
		adminGroup := v1.Group("/admin")
		adminGroup.Use(middleware.JWTAuth())
		{
			adminGroup.GET("/tasks", taskHandler.GetAllTasks)
			adminGroup.GET("/tasks/stats", taskHandler.GetAllStats)
		}
	}

	return router
}
