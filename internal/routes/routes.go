package routes

import (
	"fmt"
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

	authService := services.NewAuthService(db)
	noteService := services.NewNoteService(db)
	categoryService := services.NewCategoryService(db)
	tagService := services.NewTagService(db)
	fileService := services.NewFileService(db, cfg.File.UploadPath, cfg.File.MaxUserStorage)

	authHandler := handlers.NewAuthHandler(authService, cfg)
	noteHandler := handlers.NewNoteHandler(noteService)
	categoryHandler := handlers.NewCategoryHandler(categoryService)
	tagHandler := handlers.NewTagHandler(tagService)
	shareHandler := handlers.NewShareHandler(db, noteService, cfg) 
	fileHandler := handlers.NewFileHandler(fileService, cfg)

	api := router.Group("/api")

	public := api.Group("")
	{
		auth := public.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
		}
	}

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
			
			notes.POST("/:id/attachments", fileHandler.UploadFile)
			notes.GET("/:id/attachments", fileHandler.GetAttachments)
			
			notes.POST("/:id/share", shareHandler.CreateShareLink)
			notes.GET("/:id/share", shareHandler.GetShareInfo)
			notes.DELETE("/:id/share", shareHandler.DeleteShareLink)

			notes.GET("/:id", noteHandler.GetNote)
			notes.PUT("/:id", noteHandler.UpdateNote)
			notes.DELETE("/:id", noteHandler.DeleteNote)
		}

		attachments := protected.Group("/attachments")
		{
			attachments.DELETE("/:id", fileHandler.DeleteAttachment)
		}

		user_storage := protected.Group("/user")
		{
			user_storage.GET("/storage", fileHandler.GetUserStorage)
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

		files := protected.Group("/files")
		{
			files.GET("/:id", fileHandler.ServeFile)        
			files.GET("/:id/download", fileHandler.DownloadFile) 
		}
	}

	admin := api.Group("/admin")
	admin.Use(middleware.AuthMiddleware(db, cfg))
	admin.Use(middleware.AdminMiddleware())
	{
	}

	router.GET("/api/public/notes/:code", shareHandler.GetPublicNote)

	router.GET("/public/notes/:code", func(c *gin.Context) {
		shareCode := c.Param("code")
		frontendURL := fmt.Sprintf("%s/public/notes/%s", cfg.Frontend.BaseURL, shareCode)
		c.Redirect(302, frontendURL)
	})

	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"status":  "ok",
			"message": "服务运行正常",
		})
	})

	return router
}