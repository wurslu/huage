package models

import (
	"time"

	"gorm.io/gorm"
)

type Note struct {
	ID          uint           `json:"id" gorm:"primaryKey"`
	UserID      uint           `json:"user_id" gorm:"not null;index"`
	CategoryID  *uint          `json:"category_id" gorm:"index"`
	Title       string         `json:"title" gorm:"size:255;not null"`
	Content     string         `json:"content" gorm:"type:text"`
	ContentType string         `json:"content_type" gorm:"size:20;default:markdown"`
	IsPublic    bool           `json:"is_public" gorm:"default:false;index"`
	ViewCount   int            `json:"view_count" gorm:"default:0"`
	CreatedAt   time.Time      `json:"created_at" gorm:"index"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `json:"-" gorm:"index"`

	// 关联
	User        User         `json:"user,omitempty" gorm:"foreignKey:UserID"`
	Category    *Category    `json:"category,omitempty" gorm:"foreignKey:CategoryID"`
	Tags        []Tag        `json:"tags,omitempty" gorm:"many2many:note_tags;"`
	Attachments []Attachment `json:"attachments,omitempty" gorm:"foreignKey:NoteID"`
	ShareLinks  []ShareLink  `json:"share_links,omitempty" gorm:"foreignKey:NoteID"`
	Visits      []NoteVisit  `json:"visits,omitempty" gorm:"foreignKey:NoteID"`
}

type NoteCreateRequest struct {
	Title       string `json:"title" validate:"required,max=255"`
	Content     string `json:"content"`
	ContentType string `json:"content_type" validate:"oneof=markdown html"`
	CategoryID  *uint  `json:"category_id"`
	TagIDs      []uint `json:"tag_ids"`
	IsPublic    bool   `json:"is_public"`
}

type NoteUpdateRequest struct {
	Title       string `json:"title" validate:"required,max=255"`
	Content     string `json:"content"`
	CategoryID  *uint  `json:"category_id"`
	TagIDs      []uint `json:"tag_ids"`
	IsPublic    bool   `json:"is_public"`
}

type NoteListRequest struct {
	Page       int    `form:"page" validate:"min=1"`
	Limit      int    `form:"limit" validate:"min=1,max=100"`
	CategoryID *uint  `form:"category_id"`
	TagID      *uint  `form:"tag_id"`
	Search     string `form:"search"`
	Sort       string `form:"sort" validate:"oneof=created_at updated_at title view_count"`
	Order      string `form:"order" validate:"oneof=asc desc"`
}