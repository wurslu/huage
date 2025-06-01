// internal/routes/routes.go - 修复分享路由
package routes

import (
	"notes-backend/internal/config"
	"notes-backend/internal/handlers"
	"notes-backend/internal/middleware"
	"notes-backend/internal/services"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func Setup(db *gorm.DB, cfg *config.Config) *gin.Engine {
	router := gin.New()

	router.Use(middleware.LoggerMiddleware())
	router.Use(gin.Recovery())
	router.Use(middleware.CORSMiddleware())
	router.Use(middleware.RateLimitMiddleware(60))

	router.Static("/uploads", cfg.File.UploadPath)

	// 初始化服务层
	authService := services.NewAuthService(db)
	noteService := services.NewNoteService(db)
	categoryService := services.NewCategoryService(db)
	tagService := services.NewTagService(db)

	// 初始化处理器层
	authHandler := handlers.NewAuthHandler(authService, cfg)
	noteHandler := handlers.NewNoteHandler(noteService)
	categoryHandler := handlers.NewCategoryHandler(categoryService)
	tagHandler := handlers.NewTagHandler(tagService)
	shareHandler := handlers.NewShareHandler(db, noteService)

	api := router.Group("/api")

	// 公开路由
	public := api.Group("")
	{
		auth := public.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}
	}

	// 需要认证的路由
	protected := api.Group("")
	protected.Use(middleware.AuthMiddleware(db, cfg))
	{
		user := protected.Group("/auth")
		{
			user.GET("/me", authHandler.GetMe)
			user.POST("/logout", authHandler.Logout)
		}

		notes := protected.Group("/notes")
		{
			notes.GET("", noteHandler.GetNotes)
			notes.POST("", noteHandler.CreateNote)
			notes.GET("/stats", noteHandler.GetUserStats)
			notes.GET("/:id", noteHandler.GetNote)
			notes.PUT("/:id", noteHandler.UpdateNote)
			notes.DELETE("/:id", noteHandler.DeleteNote)
			
			// 分享相关路由 - 确保这些路由都存在
			notes.POST("/:id/share", shareHandler.CreateShareLink)    // 创建分享链接
			notes.GET("/:id/share", shareHandler.GetShareInfo)        // 获取分享信息
			notes.DELETE("/:id/share", shareHandler.DeleteShareLink)  // 删除分享链接
		}

		categories := protected.Group("/categories")
		{
			categories.GET("", categoryHandler.GetCategories)
			categories.POST("", categoryHandler.CreateCategory)
			categories.PUT("/:id", categoryHandler.UpdateCategory)
			categories.DELETE("/:id", categoryHandler.DeleteCategory)
		}

		tags := protected.Group("/tags")
		{
			tags.GET("", tagHandler.GetTags)
			tags.POST("", tagHandler.CreateTag)
			tags.PUT("/:id", tagHandler.UpdateTag)
			tags.DELETE("/:id", tagHandler.DeleteTag)
		}
	}

	// 管理员路由
	admin := api.Group("/admin")
	admin.Use(middleware.AuthMiddleware(db, cfg))
	admin.Use(middleware.AdminMiddleware())
	{
		// 管理员功能可以在这里添加
	}

	// 公开分享路由 - 不需要认证
	router.GET("/public/notes/:code", shareHandler.GetPublicNote)

	// 健康检查
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"message": "服务运行正常",
		})
	})

	return router
}