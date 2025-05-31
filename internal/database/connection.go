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

func Connect(cfg config.DatabaseConfig) (*gorm.DB, error) {
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