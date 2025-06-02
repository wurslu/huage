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
	Frontend FrontendConfig `yaml:"frontend"`
}

type FrontendConfig struct {
	BaseURL string `yaml:"base_url"`
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
	URL      string `yaml:"url"`
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

	if data, err := os.ReadFile("configs/config.yaml"); err == nil {
		if err := yaml.Unmarshal(data, cfg); err != nil {
			return nil, fmt.Errorf("failed to parse config.yaml: %w", err)
		}
	}

	cfg.overrideFromEnv()

	cfg.setDefaults()

	if err := cfg.configureDatabaseByMode(); err != nil {
		return nil, fmt.Errorf("database configuration failed: %w", err)
	}

	return cfg, nil
}

func (c *Config) configureDatabaseByMode() error {
	dbMode := os.Getenv("DB_MODE")
	if dbMode == "" {
		dbMode = "local"
	}

	fmt.Printf("database mode: %s\n", dbMode)

	switch dbMode {
	case "local":
		return c.configureLocalDatabase()
	case "vercel":
		return c.configureVercelDatabase()
	case "custom":
		return c.configureCustomDatabase()
	default:
		return fmt.Errorf("unknown database mode: %s", dbMode)
	}
}

func (c *Config) configureLocalDatabase() error {
	fmt.Println("configuring local database...")
	
	c.Database.Host = getEnvOrDefault("LOCAL_DB_HOST", "postgres")
	c.Database.User = getEnvOrDefault("LOCAL_DB_USER", "notes_user")
	c.Database.Password = getEnvOrDefault("LOCAL_DB_PASSWORD", "notes_password_2024")
	c.Database.DBName = getEnvOrDefault("LOCAL_DB_NAME", "notes_db")
	c.Database.SSLMode = "disable"
	
	if portStr := os.Getenv("LOCAL_DB_PORT"); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil {
			c.Database.Port = port
		}
	} else {
		c.Database.Port = 5432
	}

	c.Database.URL = ""
	
	fmt.Printf("local database config: %s@%s:%d/%s\n", 
		c.Database.User, c.Database.Host, c.Database.Port, c.Database.DBName)
	
	return nil
}

func (c *Config) configureVercelDatabase() error {
	fmt.Println("configuring Vercel database...")
	
	if url := os.Getenv("VERCEL_POSTGRES_URL"); url != "" {
		c.Database.URL = url
		c.Database.SSLMode = "require"
		fmt.Println("using Vercel POSTGRES_URL")
		return nil
	}

	c.Database.Host = os.Getenv("VERCEL_POSTGRES_HOST")
	c.Database.User = os.Getenv("VERCEL_POSTGRES_USER")
	c.Database.Password = os.Getenv("VERCEL_POSTGRES_PASSWORD")
	c.Database.DBName = os.Getenv("VERCEL_POSTGRES_DATABASE")
	c.Database.Port = 5432
	c.Database.SSLMode = "require"
	c.Database.URL = ""

	if c.Database.Host == "" || c.Database.User == "" {
		return fmt.Errorf("vercel database configuration incomplete, please set VERCEL_POSTGRES_URL or VERCEL_POSTGRES_* parameters")
	}

	fmt.Printf("vercel database config: %s@%s:%d/%s\n", 
		c.Database.User, c.Database.Host, c.Database.Port, c.Database.DBName)
	
	return nil
}

func (c *Config) configureCustomDatabase() error {
	fmt.Println("configuring custom database...")
	
	if url := os.Getenv("CUSTOM_DB_URL"); url != "" {
		c.Database.URL = url
		c.Database.SSLMode = getEnvOrDefault("CUSTOM_DB_SSLMODE", "disable")
		fmt.Println("using custom database URL")
		return nil
	}

	c.Database.Host = os.Getenv("CUSTOM_DB_HOST")
	c.Database.User = os.Getenv("CUSTOM_DB_USER")
	c.Database.Password = os.Getenv("CUSTOM_DB_PASSWORD")
	c.Database.DBName = os.Getenv("CUSTOM_DB_NAME")
	c.Database.SSLMode = getEnvOrDefault("CUSTOM_DB_SSLMODE", "disable")
	c.Database.URL = ""

	if portStr := os.Getenv("CUSTOM_DB_PORT"); portStr != "" {
		if port, err := strconv.Atoi(portStr); err == nil {
			c.Database.Port = port
		}
	} else {
		c.Database.Port = 5432
	}

	if c.Database.Host == "" || c.Database.User == "" {
		return fmt.Errorf("custom database configuration incomplete, please set related parameters")
	}

	fmt.Printf("custom database config: %s@%s:%d/%s\n", 
		c.Database.User, c.Database.Host, c.Database.Port, c.Database.DBName)
	
	return nil
}

func (c *Config) overrideFromEnv() {
	if val := os.Getenv("JWT_SECRET"); val != "" {
		c.JWT.Secret = val
	}

	if val := os.Getenv("SERVER_PORT"); val != "" {
		if port, err := strconv.Atoi(val); err == nil {
			c.Server.Port = port
		}
	}
	if val := os.Getenv("GIN_MODE"); val != "" {
		c.Server.Mode = val
	}

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
	if val := os.Getenv("FRONTEND_BASE_URL"); val != "" {
		c.Frontend.BaseURL = val
	}
}

func (c *Config) setDefaults() {
	if c.Server.Port == 0 {
		c.Server.Port = 9191
	}
	if c.Server.Mode == "" {
		c.Server.Mode = "debug"
	}

	if c.JWT.ExpireHours == 0 {
		c.JWT.ExpireHours = 24
	}

	if c.File.UploadPath == "" {
		c.File.UploadPath = "./uploads"
	}
	if c.File.MaxImageSize == 0 {
		c.File.MaxImageSize = 10485760
	}
	if c.File.MaxDocumentSize == 0 {
		c.File.MaxDocumentSize = 52428800
	}
	if c.File.MaxUserStorage == 0 {
		c.File.MaxUserStorage = 524288000
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
	if c.Frontend.BaseURL == "" {
		c.Frontend.BaseURL = "https://huage.api.withgo.cn"
	}
}

func (c *Config) GetDSN() string {
	if c.Database.URL != "" {
		return c.Database.URL
	}
	
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

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}