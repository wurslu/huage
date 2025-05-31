package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	JWT      JWTConfig      `yaml:"jwt"`
	File     FileConfig     `yaml:"file"`
	Backup   BackupConfig   `yaml:"backup"`
	Log      LogConfig      `yaml:"log"`
}

type ServerConfig struct {
	Port int    `yaml:"port"`
	Mode string `yaml:"mode"`
}

type DatabaseConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
	DBName   string `yaml:"dbname"`
	SSLMode  string `yaml:"sslmode"`
}

type JWTConfig struct {
	Secret      string `yaml:"secret"`
	ExpireHours int    `yaml:"expire_hours"`
}

type FileConfig struct {
	UploadPath           string   `yaml:"upload_path"`
	MaxImageSize         int64    `yaml:"max_image_size"`
	MaxDocumentSize      int64    `yaml:"max_document_size"`
	MaxUserStorage       int64    `yaml:"max_user_storage"`
	AllowedImageTypes    []string `yaml:"allowed_image_types"`
	AllowedDocumentTypes []string `yaml:"allowed_document_types"`
}

type BackupConfig struct {
	Enabled  bool   `yaml:"enabled"`
	Path     string `yaml:"path"`
	Schedule string `yaml:"schedule"`
	KeepDays int    `yaml:"keep_days"`
}

type LogConfig struct {
	Level      string `yaml:"level"`
	File       string `yaml:"file"`
	MaxSize    int    `yaml:"max_size"`
	MaxAge     int    `yaml:"max_age"`
	MaxBackups int    `yaml:"max_backups"`
}

func Load() (*Config, error) {
	cfg := &Config{}

	// 首先尝试从 YAML 文件加载
	if data, err := os.ReadFile("configs/config.yaml"); err == nil {
		if err := yaml.Unmarshal(data, cfg); err != nil {
			return nil, err
		}
	}

	// 然后从环境变量覆盖
	cfg.overrideFromEnv()

	// 设置默认值
	cfg.setDefaults()

	return cfg, nil
}

func (c *Config) overrideFromEnv() {
	// Database
	if val := os.Getenv("DB_HOST"); val != "" {
		c.Database.Host = val
	}
	if val := os.Getenv("DB_PORT"); val != "" {
		if port, err := strconv.Atoi(val); err == nil {
			c.Database.Port = port
		}
	}
	if val := os.Getenv("DB_USER"); val != "" {
		c.Database.User = val
	}
	if val := os.Getenv("DB_PASSWORD"); val != "" {
		c.Database.Password = val
	}
	if val := os.Getenv("DB_NAME"); val != "" {
		c.Database.DBName = val
	}

	// JWT
	if val := os.Getenv("JWT_SECRET"); val != "" {
		c.JWT.Secret = val
	}

	// Server
	if val := os.Getenv("SERVER_PORT"); val != "" {
		if port, err := strconv.Atoi(val); err == nil {
			c.Server.Port = port
		}
	}
	if val := os.Getenv("GIN_MODE"); val != "" {
		c.Server.Mode = val
	}

	// File
	if val := os.Getenv("UPLOAD_PATH"); val != "" {
		c.File.UploadPath = val
	}
	if val := os.Getenv("MAX_IMAGE_SIZE"); val != "" {
		if size, err := strconv.ParseInt(val, 10, 64); err == nil {
			c.File.MaxImageSize = size
		}
	}
	if val := os.Getenv("MAX_DOCUMENT_SIZE"); val != "" {
		if size, err := strconv.ParseInt(val, 10, 64); err == nil {
			c.File.MaxDocumentSize = size
		}
	}
	if val := os.Getenv("MAX_USER_STORAGE"); val != "" {
		if size, err := strconv.ParseInt(val, 10, 64); err == nil {
			c.File.MaxUserStorage = size
		}
	}
}

func (c *Config) setDefaults() {
	if c.Server.Port == 0 {
		c.Server.Port = 8080
	}
	if c.Server.Mode == "" {
		c.Server.Mode = "debug"
	}

	if c.Database.Host == "" {
		c.Database.Host = "localhost"
	}
	if c.Database.Port == 0 {
		c.Database.Port = 5432
	}
	if c.Database.SSLMode == "" {
		c.Database.SSLMode = "disable"
	}

	if c.JWT.ExpireHours == 0 {
		c.JWT.ExpireHours = 24
	}

	if c.File.UploadPath == "" {
		c.File.UploadPath = "./uploads"
	}
	if c.File.MaxImageSize == 0 {
		c.File.MaxImageSize = 10485760 // 10MB
	}
	if c.File.MaxDocumentSize == 0 {
		c.File.MaxDocumentSize = 52428800 // 50MB
	}
	if c.File.MaxUserStorage == 0 {
		c.File.MaxUserStorage = 524288000 // 500MB
	}
	if len(c.File.AllowedImageTypes) == 0 {
		c.File.AllowedImageTypes = []string{"jpg", "jpeg", "png", "gif", "webp"}
	}
	if len(c.File.AllowedDocumentTypes) == 0 {
		c.File.AllowedDocumentTypes = []string{"pdf", "doc", "docx", "xls", "xlsx"}
	}

	if c.Log.Level == "" {
		c.Log.Level = "info"
	}
	if c.Log.File == "" {
		c.Log.File = "./logs/app.log"
	}
}

func (c *Config) GetDSN() string {
	return fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Database.Host, c.Database.Port, c.Database.User,
		c.Database.Password, c.Database.DBName, c.Database.SSLMode)
}

func (c *Config) IsImageType(fileType string) bool {
	fileType = strings.ToLower(fileType)
	for _, allowedType := range c.File.AllowedImageTypes {
		if fileType == allowedType {
			return true
		}
	}
	return false
}

func (c *Config) IsDocumentType(fileType string) bool {
	fileType = strings.ToLower(fileType)
	for _, allowedType := range c.File.AllowedDocumentTypes {
		if fileType == allowedType {
			return true
		}
	}
	return false
}