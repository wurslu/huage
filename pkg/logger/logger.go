// pkg/logger/logger.go
package logger

import (
	"io"
	"notes-backend/internal/config"
	"os"
	"path/filepath"

	"github.com/sirupsen/logrus"
	"gopkg.in/natefinch/lumberjack.v2"
)

func Init(cfg config.LogConfig) {
	// 设置日志级别
	level, err := logrus.ParseLevel(cfg.Level)
	if err != nil {
		level = logrus.InfoLevel
	}
	logrus.SetLevel(level)

	// 设置日志格式
	logrus.SetFormatter(&logrus.JSONFormatter{
		TimestampFormat: "2006-01-02 15:04:05",
	})

	// 创建日志目录
	if cfg.File != "" {
		logDir := filepath.Dir(cfg.File)
		if err := os.MkdirAll(logDir, 0755); err != nil {
			logrus.WithError(err).Warn("无法创建日志目录")
		}
	}

	// 配置日志输出
	var writers []io.Writer

	// 控制台输出
	writers = append(writers, os.Stdout)

	// 文件输出
	if cfg.File != "" {
		fileWriter := &lumberjack.Logger{
			Filename:   cfg.File,
			MaxSize:    cfg.MaxSize,    // MB
			MaxAge:     cfg.MaxAge,     // days
			MaxBackups: cfg.MaxBackups,
			LocalTime:  true,
			Compress:   true,
		}
		writers = append(writers, fileWriter)
	}

	// 设置多重输出
	multiWriter := io.MultiWriter(writers...)
	logrus.SetOutput(multiWriter)

	logrus.Info("日志系统初始化完成")
}

func GetLogger() *logrus.Logger {
	return logrus.StandardLogger()
}