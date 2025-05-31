package models

import "time"
type ShareLink struct {
	ID         uint       `json:"id" gorm:"primaryKey"`
	NoteID     uint       `json:"note_id" gorm:"not null;index"`
	ShareCode  string     `json:"share_code" gorm:"size:32;uniqueIndex;not null"`
	Password   *string    `json:"password,omitempty" gorm:"size:255"`
	ExpireTime *time.Time `json:"expire_time"`
	VisitCount int        `json:"visit_count" gorm:"default:0"`
	IsActive   bool       `json:"is_active" gorm:"default:true"`
	CreatedAt  time.Time  `json:"created_at"`

	Note Note `json:"note,omitempty" gorm:"foreignKey:NoteID"`
}
