package models

import "time"

type NoteVisit struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	NoteID    uint      `json:"note_id" gorm:"not null;index"`
	ViewerID  *uint     `json:"viewer_id" gorm:"index"` 
	VisitorIP *string   `json:"visitor_ip" gorm:"type:inet"`
	UserAgent *string   `json:"user_agent" gorm:"type:text"`
	Referer   *string   `json:"referer" gorm:"type:text"`
	ViewHash  *string   `json:"view_hash" gorm:"size:32;index"` 
	VisitedAt time.Time `json:"visited_at" gorm:"index;default:CURRENT_TIMESTAMP"`

	Note   Note  `json:"note,omitempty" gorm:"foreignKey:NoteID"`
	Viewer *User `json:"viewer,omitempty" gorm:"foreignKey:ViewerID"`
}

type ViewerInfo struct {
	IP        string
	UserAgent string
	Referer   string
}