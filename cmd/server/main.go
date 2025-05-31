package main

import (
	"fmt"
	"log"
	"notes-backend/internal/config"
	"notes-backend/internal/database"
	"notes-backend/internal/routes"
	"notes-backend/pkg/logger"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// 加载环境变量
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	// 初始化配置
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// 初始化日志
	logger.Init(cfg.Log)

	// 设置 Gin 模式
	gin.SetMode(cfg.Server.Mode)

	// 初始化数据库
	db, err := database.Connect(cfg.Database)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	// 运行数据库自动迁移
	if err := database.AutoMigrate(); err != nil {
		log.Fatalf("Failed to auto migrate: %v", err)
	}

	log.Println("数据库自动迁移完成")

	// 创建上传目录
	if err := createUploadDirs(cfg.File.UploadPath); err != nil {
		log.Fatalf("Failed to create upload directories: %v", err)
	}

	// 初始化路由
	router := routes.Setup(db, cfg)

	// 启动服务器
	addr := fmt.Sprintf(":%d", cfg.Server.Port)
	log.Printf("Server starting on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func createUploadDirs(basePath string) error {
	dirs := []string{
		basePath,
		basePath + "/users",
		basePath + "/temp",
	}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return err
		}
	}

	return nil
}