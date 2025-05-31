package models

import (
	"time"

	"gorm.io/gorm"
)

type Category struct {
	ID          uint           `json:"id" gorm:"primaryKey"`
	UserID      uint           `json:"user_id" gorm:"not null;index"`
	Name        string         `json:"name" gorm:"size:100;not null"`
	ParentID    *uint          `json:"parent_id" gorm:"index"`
	SortOrder   int            `json:"sort_order" gorm:"default:0"`
	Description *string        `json:"description" gorm:"type:text"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`

	// 关联
	User     User       `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Parent   *Category  `json:"parent,omitempty" gorm:"foreignKey:ParentID"`
	Children []Category `json:"children,omitempty" gorm:"foreignKey:ParentID"`
	Notes    []Note     `json:"notes,omitempty" gorm:"foreignKey:CategoryID"`

	// 计算字段
	NoteCount int `json:"note_count,omitempty" gorm:"-"`
}

type CategoryCreateRequest struct {
	Name        string  `json:"name" validate:"required,max=100"`
	ParentID    *uint   `json:"parent_id"`
	Description *string `json:"description"`
}