package models

import (
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID           uint           `json:"id" gorm:"primaryKey"`
	Username     string         `json:"username" gorm:"uniqueIndex;size:50;not null"`
	Email        string         `json:"email" gorm:"uniqueIndex;size:100;not null"`
	PasswordHash string         `json:"-" gorm:"size:255;not null"`
	Avatar       *string        `json:"avatar" gorm:"size:255"`
	Role         string         `json:"role" gorm:"size:20;default:user"`
	IsActive     bool           `json:"is_active" gorm:"default:true"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `json:"-" gorm:"index"`

	// 关联
	Categories []Category `json:"categories,omitempty" gorm:"foreignKey:UserID"`
	Tags       []Tag      `json:"tags,omitempty" gorm:"foreignKey:UserID"`
	Notes      []Note     `json:"notes,omitempty" gorm:"foreignKey:UserID"`
}

type UserRegisterRequest struct {
	Username string `json:"username" validate:"required,min=3,max=50"`
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required,min=6"`
}

type UserLoginRequest struct {
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required"`
}

type UserResponse struct {
	User  *User  `json:"user"`
	Token string `json:"token"`
}

type UserStorage struct {
	UserID        uint      `json:"user_id" gorm:"primaryKey"`
	UsedSpace     int64     `json:"used_space" gorm:"default:0"`
	FileCount     int       `json:"file_count" gorm:"default:0"`
	ImageCount    int       `json:"image_count" gorm:"default:0"`
	DocumentCount int       `json:"document_count" gorm:"default:0"`
	UpdatedAt     time.Time `json:"updated_at"`

	// 关联
	User User `json:"user,omitempty" gorm:"foreignKey:UserID"`
}