package services

import (
	"fmt"
	"math"
	"notes-backend/internal/models"

	"gorm.io/gorm"
)

type NoteService struct {
	db *gorm.DB
}

type UserStats struct {
	TotalNotes      int64 `json:"total_notes"`
	PublicNotes     int64 `json:"public_notes"`
	PrivateNotes    int64 `json:"private_notes"`
	TotalCategories int64 `json:"total_categories"`
	TotalTags       int64 `json:"total_tags"`
	TotalViews      int64 `json:"total_views"`
}


func NewNoteService(db *gorm.DB) *NoteService {
	return &NoteService{db: db}
}

func (s *NoteService) GetNotes(userID uint, req *models.NoteListRequest) ([]models.Note, *models.Pagination, error) {
	var notes []models.Note
	var total int64

	query := s.db.Model(&models.Note{}).Where("user_id = ?", userID)

	if req.CategoryID != nil {
		query = query.Where("category_id = ?", *req.CategoryID)
	}

	if req.Search != "" {
		query = query.Where("title ILIKE ? OR content ILIKE ?", "%"+req.Search+"%", "%"+req.Search+"%")
	}

	if req.TagID != nil {
		query = query.Joins("JOIN note_tags ON notes.id = note_tags.note_id").Where("note_tags.tag_id = ?", *req.TagID)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, nil, err
	}

	offset := (req.Page - 1) * req.Limit
	pages := int(math.Ceil(float64(total) / float64(req.Limit)))

	orderBy := "created_at DESC"
	if req.Sort != "" {
		direction := "DESC"
		if req.Order == "asc" {
			direction = "ASC"
		}
		orderBy = fmt.Sprintf("%s %s", req.Sort, direction)
	}

	err := query.Preload("Category").Preload("Tags").Preload("Attachments").
		Order(orderBy).Limit(req.Limit).Offset(offset).Find(&notes).Error
	if err != nil {
		return nil, nil, err
	}

	pagination := &models.Pagination{
		Page:  req.Page,
		Limit: req.Limit,
		Total: int(total),
		Pages: pages,
	}

	return notes, pagination, nil
}

func (s *NoteService) GetNoteByID(noteID, userID uint) (*models.Note, error) {
	var note models.Note
	err := s.db.Preload("Category").Preload("Tags").Preload("Attachments").
		Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error
	if err != nil {
		return nil, err
	}
	return &note, nil
}

func (s *NoteService) CreateNote(userID uint, req *models.NoteCreateRequest) (*models.Note, error) {
	note := models.Note{
		UserID:      userID,
		CategoryID:  req.CategoryID,
		Title:       req.Title,
		Content:     req.Content,
		ContentType: req.ContentType,
		IsPublic:    req.IsPublic,
		ViewCount:   0,
	}

	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&note).Error; err != nil {
			return err
		}

		if len(req.TagIDs) > 0 {
			var tags []models.Tag
			if err := tx.Where("id IN ? AND user_id = ?", req.TagIDs, userID).Find(&tags).Error; err != nil {
				return err
			}
			if err := tx.Model(&note).Association("Tags").Append(tags); err != nil {
				return err
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	s.db.Preload("Category").Preload("Tags").Preload("Attachments").First(&note, note.ID)

	return &note, nil
}

func (s *NoteService) UpdateNote(noteID, userID uint, req *models.NoteUpdateRequest) (*models.Note, error) {
	var note models.Note
	
	if err := s.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		return nil, err
	}

	err := s.db.Transaction(func(tx *gorm.DB) error {
		updates := map[string]interface{}{
			"title":       req.Title,
			"content":     req.Content,
			"category_id": req.CategoryID,
			"is_public":   req.IsPublic,
		}
		
		if err := tx.Model(&note).Updates(updates).Error; err != nil {
			return err
		}

		if err := tx.Model(&note).Association("Tags").Clear(); err != nil {
			return err
		}

		if len(req.TagIDs) > 0 {
			var tags []models.Tag
			if err := tx.Where("id IN ? AND user_id = ?", req.TagIDs, userID).Find(&tags).Error; err != nil {
				return err
			}
			if err := tx.Model(&note).Association("Tags").Append(tags); err != nil {
				return err
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	s.db.Preload("Category").Preload("Tags").Preload("Attachments").First(&note, note.ID)

	return &note, nil
}

func (s *NoteService) DeleteNote(noteID, userID uint) error {
	result := s.db.Where("id = ? AND user_id = ?", noteID, userID).Delete(&models.Note{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("笔记不存在或无权限删除")
	}
	return nil
}

func (s *NoteService) GetUserStats(userID uint) (*UserStats, error) {
	var stats UserStats

	if err := s.db.Model(&models.Note{}).Where("user_id = ?", userID).Count(&stats.TotalNotes).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Note{}).Where("user_id = ? AND is_public = ?", userID, true).Count(&stats.PublicNotes).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Note{}).Where("user_id = ? AND is_public = ?", userID, false).Count(&stats.PrivateNotes).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Category{}).Where("user_id = ?", userID).Count(&stats.TotalCategories).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Tag{}).Where("user_id = ?", userID).Count(&stats.TotalTags).Error; err != nil {
		return nil, err
	}

	if err := s.db.Model(&models.Note{}).Where("user_id = ?", userID).Select("COALESCE(SUM(view_count), 0)").Scan(&stats.TotalViews).Error; err != nil {
		return nil, err
	}

	return &stats, nil
}