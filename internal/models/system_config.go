package models

import "time"


type SystemConfig struct {
	Key         string    `json:"key" gorm:"primaryKey;size:100"`
	Value       string    `json:"value" gorm:"type:text"`
	Description string    `json:"description" gorm:"type:text"`
	UpdatedAt   time.Time `json:"updated_at"`

	IsActive   bool       `json:"is_active" db:"is_active"`
	CreatedAt  time.Time  `json:"created_at" db:"created_at"`
}

type ShareLinkCreateRequest struct {
	Password   *string    `json:"password"`
	ExpireTime *time.Time `json:"expire_time"`
}

type ShareLinkResponse struct {
	ShareCode  string     `json:"share_code"`
	ShareURL   string     `json:"share_url"`
	Password   *string    `json:"password,omitempty"`
	ExpireTime *time.Time `json:"expire_time,omitempty"`
}