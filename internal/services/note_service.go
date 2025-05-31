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

func NewNoteService(db *gorm.DB) *NoteService {
	return &NoteService{db: db}
}

func (s *NoteService) GetNotes(userID uint, req *models.NoteListRequest) ([]models.Note, *models.Pagination, error) {
	var notes []models.Note
	var total int64

	// 构建查询
	query := s.db.Model(&models.Note{}).Where("user_id = ?", userID)

	// 添加条件
	if req.CategoryID != nil {
		query = query.Where("category_id = ?", *req.CategoryID)
	}

	if req.Search != "" {
		query = query.Where("title ILIKE ? OR content ILIKE ?", "%"+req.Search+"%", "%"+req.Search+"%")
	}

	if req.TagID != nil {
		query = query.Joins("JOIN note_tags ON notes.id = note_tags.note_id").Where("note_tags.tag_id = ?", *req.TagID)
	}

	// 计算总数
	if err := query.Count(&total).Error; err != nil {
		return nil, nil, err
	}

	// 分页
	offset := (req.Page - 1) * req.Limit
	pages := int(math.Ceil(float64(total) / float64(req.Limit)))

	// 排序
	orderBy := "created_at DESC"
	if req.Sort != "" {
		direction := "DESC"
		if req.Order == "asc" {
			direction = "ASC"
		}
		orderBy = fmt.Sprintf("%s %s", req.Sort, direction)
	}

	// 查询数据
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

	// 使用事务
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// 创建笔记
		if err := tx.Create(&note).Error; err != nil {
			return err
		}

		// 添加标签关联
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

	// 重新加载关联数据
	s.db.Preload("Category").Preload("Tags").Preload("Attachments").First(&note, note.ID)

	return &note, nil
}

func (s *NoteService) UpdateNote(noteID, userID uint, req *models.NoteUpdateRequest) (*models.Note, error) {
	var note models.Note
	
	// 先查找笔记
	if err := s.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		return nil, err
	}

	// 使用事务更新
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// 更新笔记基本信息
		updates := map[string]interface{}{
			"title":       req.Title,
			"content":     req.Content,
			"category_id": req.CategoryID,
			"is_public":   req.IsPublic,
		}
		
		if err := tx.Model(&note).Updates(updates).Error; err != nil {
			return err
		}

		// 更新标签关联
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

	// 重新加载关联数据
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
