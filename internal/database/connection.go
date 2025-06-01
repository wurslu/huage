// internal/database/connection.go - 添加自动创建数据库功能
package database

import (
	"fmt"
	"notes-backend/internal/config"
	"notes-backend/internal/models"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// createDatabaseIfNotExists 如果数据库不存在则创建
func createDatabaseIfNotExists(cfg config.DatabaseConfig) error {
	// 连接到 postgres 默认数据库来创建目标数据库
	defaultDSN := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=postgres sslmode=%s",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.SSLMode)

	db, err := gorm.Open(postgres.Open(defaultDSN), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent), // 静默模式，避免过多日志
	})
	if err != nil {
		return fmt.Errorf("failed to connect to postgres database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return fmt.Errorf("failed to get sql.DB: %w", err)
	}
	defer sqlDB.Close()

	// 检查数据库是否存在
	var exists bool
	checkSQL := "SELECT EXISTS(SELECT datname FROM pg_catalog.pg_database WHERE datname = $1)"
	err = db.Raw(checkSQL, cfg.DBName).Scan(&exists).Error
	if err != nil {
		return fmt.Errorf("failed to check database existence: %w", err)
	}

	// 如果数据库不存在，则创建
	if !exists {
		createSQL := fmt.Sprintf("CREATE DATABASE %s", cfg.DBName)
		err = db.Exec(createSQL).Error
		if err != nil {
			return fmt.Errorf("failed to create database %s: %w", cfg.DBName, err)
		}
		fmt.Printf("数据库 '%s' 创建成功\n", cfg.DBName)
	} else {
		fmt.Printf("数据库 '%s' 已存在\n", cfg.DBName)
	}

	return nil
}

func Connect(cfg config.DatabaseConfig) (*gorm.DB, error) {
	// 首先尝试创建数据库（如果不存在）
	if err := createDatabaseIfNotExists(cfg); err != nil {
		return nil, err
	}

	// 连接到目标数据库
	dsn := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// 获取底层的 sql.DB 来设置连接池参数
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get sql.DB: %w", err)
	}

	// 设置连接池参数
	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(5)

	DB = db
	return db, nil
}

func AutoMigrate() error {
	if DB == nil {
		return fmt.Errorf("database connection not initialized")
	}

	// 自动迁移所有模型
	err := DB.AutoMigrate(
		&models.User{},
		&models.Category{},
		&models.Tag{},
		&models.Note{},
		&models.Attachment{},
		&models.ShareLink{},
		&models.NoteVisit{},
		&models.UserStorage{},
		&models.SystemConfig{},
	)

	if err != nil {
		return fmt.Errorf("failed to auto migrate: %w", err)
	}

	// 插入默认系统配置
	if err := insertDefaultConfigs(); err != nil {
		return fmt.Errorf("failed to insert default configs: %w", err)
	}

	return nil
}

func insertDefaultConfigs() error {
	defaultConfigs := []models.SystemConfig{
		{Key: "max_file_size_image", Value: "10485760", Description: "单个图片最大大小(字节) - 10MB"},
		{Key: "max_file_size_document", Value: "52428800", Description: "单个文档最大大小(字节) - 50MB"},
		{Key: "max_user_storage", Value: "524288000", Description: "用户最大存储空间(字节) - 500MB"},
		{Key: "allowed_image_types", Value: "jpg,jpeg,png,gif,webp", Description: "允许的图片格式"},
		{Key: "allowed_document_types", Value: "pdf,doc,docx,xls,xlsx", Description: "允许的文档格式"},
	}

	for _, config := range defaultConfigs {
		var existing models.SystemConfig
		if err := DB.Where("key = ?", config.Key).First(&existing).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				// 配置不存在，创建新的
				if err := DB.Create(&config).Error; err != nil {
					return err
				}
			} else {
				return err
			}
		}
	}

	return nil
}