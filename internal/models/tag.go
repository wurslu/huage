package models

import (
	"time"

	"gorm.io/gorm"
)

type Tag struct {
	ID        uint           `json:"id" gorm:"primaryKey"`
	UserID    uint           `json:"user_id" gorm:"not null;index"`
	Name      string         `json:"name" gorm:"size:50;not null"`
	Color     string         `json:"color" gorm:"size:7;default:#1976d2"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `json:"-" gorm:"index"`

	// 关联
	User  User   `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Notes []Note `json:"notes,omitempty" gorm:"many2many:note_tags;"`

	// 计算字段
	NoteCount int `json:"note_count,omitempty" gorm:"-"`
}

// 复合唯一索引
func (Tag) TableName() string {
	return "tags"
}

type TagCreateRequest struct {
	Name  string `json:"name" validate:"required,max=50"`
	Color string `json:"color" validate:"required,hexcolor"`
}
