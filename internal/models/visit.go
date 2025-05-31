package models

import "time"
type NoteVisit struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	NoteID    uint      `json:"note_id" gorm:"not null;index"`
	VisitorIP *string   `json:"visitor_ip" gorm:"type:inet"`
	UserAgent *string   `json:"user_agent" gorm:"type:text"`
	Referer   *string   `json:"referer" gorm:"type:text"`
	VisitedAt time.Time `json:"visited_at" gorm:"index;default:CURRENT_TIMESTAMP"`

	// 关联
	Note Note `json:"note,omitempty" gorm:"foreignKey:NoteID"`
}
