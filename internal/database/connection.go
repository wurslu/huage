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

func createDatabaseIfNotExists(cfg config.DatabaseConfig) error {
	if cfg.URL != "" {
		fmt.Println("使用完整数据库 URL，跳过数据库创建检查")
		return nil
	}

	defaultDSN := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=postgres sslmode=%s",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.SSLMode)

	db, err := gorm.Open(postgres.Open(defaultDSN), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		return fmt.Errorf("failed to connect to postgres database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return fmt.Errorf("failed to get sql.DB: %w", err)
	}
	defer sqlDB.Close()

	var exists bool
	checkSQL := "SELECT EXISTS(SELECT datname FROM pg_catalog.pg_database WHERE datname = $1)"
	err = db.Raw(checkSQL, cfg.DBName).Scan(&exists).Error
	if err != nil {
		return fmt.Errorf("failed to check database existence: %w", err)
	}

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
	var dsn string
	var shouldCreateDB bool = true

	if cfg.URL != "" {
		dsn = cfg.URL
		shouldCreateDB = false
		fmt.Println("使用数据库 URL 连接")
	} else {
		dsn = fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
			cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.DBName, cfg.SSLMode)
		fmt.Println("使用传统数据库参数连接")
	}

	if shouldCreateDB {
		if err := createDatabaseIfNotExists(cfg); err != nil {
			fmt.Printf("警告：创建数据库失败，尝试直接连接: %v\n", err)
		}
	}

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get sql.DB: %w", err)
	}

	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(5)

	if err := sqlDB.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	DB = db
	fmt.Println("数据库连接成功")
	return db, nil
}

func AutoMigrate() error {
	if DB == nil {
		return fmt.Errorf("database connection not initialized")
	}

	fmt.Println("开始数据库迁移...")

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

	fmt.Println("数据库迁移完成")

	if err := insertDefaultConfigs(); err != nil {
		return fmt.Errorf("failed to insert default configs: %w", err)
	}

	fmt.Println("默认配置插入完成")
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