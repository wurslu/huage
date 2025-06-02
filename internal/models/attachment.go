// internal/models/attachment.go - 添加软删除支持
package models

import (
	"time"

	"gorm.io/gorm"
)

type Attachment struct {
	ID               uint           `json:"id" gorm:"primaryKey"`
	NoteID           uint           `json:"note_id" gorm:"not null;index"`
	Filename         string         `json:"filename" gorm:"size:255;not null"`
	OriginalFilename string         `json:"original_filename" gorm:"size:255;not null"`
	FilePath         string         `json:"file_path" gorm:"size:500;not null"`
	FileSize         int64          `json:"file_size" gorm:"not null"`
	FileType         string         `json:"file_type" gorm:"size:100;not null"`
	MimeType         *string        `json:"mime_type" gorm:"size:100"`
	IsImage          bool           `json:"is_image" gorm:"default:false"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `json:"-" gorm:"index"` // 添加软删除支持

	// 关联
	Note Note `json:"note,omitempty" gorm:"foreignKey:NoteID"`

	// 计算字段
	URLs *FileURLs `json:"urls,omitempty" gorm:"-"`
}

type FileURLs struct {
	Original  string `json:"original"`
	Medium    string `json:"medium,omitempty"`
	Thumbnail string `json:"thumbnail,omitempty"`
}