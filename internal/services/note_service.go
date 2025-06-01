// internal/services/note_service.go - 修复删除方法
package services

import (
	"crypto/md5"
	"fmt"
	"math"
	"notes-backend/internal/models"
	"time"

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

// DeleteNote 删除笔记 - 修复版本，添加详细日志和错误处理
func (s *NoteService) DeleteNote(noteID, userID uint) error {
	fmt.Printf("NoteService.DeleteNote called: noteID=%d, userID=%d\n", noteID, userID)

	// 使用事务确保数据一致性
	return s.db.Transaction(func(tx *gorm.DB) error {
		// 1. 先检查笔记是否存在
		var note models.Note
		if err := tx.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				fmt.Printf("Note not found: noteID=%d, userID=%d\n", noteID, userID)
				return fmt.Errorf("笔记不存在或无权限删除")
			}
			fmt.Printf("Error finding note: %v\n", err)
			return err
		}

		fmt.Printf("Found note to delete: %+v\n", note)

		// 2. 删除相关的标签关联（多对多关系）
		if err := tx.Model(&note).Association("Tags").Clear(); err != nil {
			fmt.Printf("Error clearing note tags: %v\n", err)
			return fmt.Errorf("删除标签关联失败: %v", err)
		}

		// 3. 删除相关的附件
		if err := tx.Where("note_id = ?", noteID).Delete(&models.Attachment{}).Error; err != nil {
			fmt.Printf("Error deleting attachments: %v\n", err)
			return fmt.Errorf("删除附件失败: %v", err)
		}

		// 4. 删除相关的分享链接
		if err := tx.Where("note_id = ?", noteID).Delete(&models.ShareLink{}).Error; err != nil {
			fmt.Printf("Error deleting share links: %v\n", err)
			return fmt.Errorf("删除分享链接失败: %v", err)
		}

		// 5. 删除相关的访问记录
		if err := tx.Where("note_id = ?", noteID).Delete(&models.NoteVisit{}).Error; err != nil {
			fmt.Printf("Error deleting note visits: %v\n", err)
			return fmt.Errorf("删除访问记录失败: %v", err)
		}

		// 6. 最后删除笔记本身（软删除）
		result := tx.Delete(&note)
		if result.Error != nil {
			fmt.Printf("Error deleting note: %v\n", result.Error)
			return fmt.Errorf("删除笔记失败: %v", result.Error)
		}

		if result.RowsAffected == 0 {
			fmt.Printf("No rows affected when deleting note: noteID=%d\n", noteID)
			return fmt.Errorf("笔记不存在或无权限删除")
		}

		fmt.Printf("Note deleted successfully: noteID=%d, rowsAffected=%d\n", noteID, result.RowsAffected)
		return nil
	})
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

	var totalViews int64
	if err := s.db.Model(&models.Note{}).Where("user_id = ?", userID).Select("COALESCE(SUM(view_count), 0)").Scan(&totalViews).Error; err != nil {
		return nil, err
	}
	stats.TotalViews = totalViews

	return &stats, nil
}

func (s *NoteService) RecordView(noteID, viewerID uint, clientIP, userAgent, viewHash string) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var note models.Note
		if err := tx.Where("id = ?", noteID).First(&note).Error; err != nil {
			return err
		}

		if note.UserID == viewerID {
			return nil
		}

		var existingVisit models.NoteVisit
		oneHourAgo := time.Now().Add(-1 * time.Hour)
		
		err := tx.Where("note_id = ? AND visitor_ip = ? AND visited_at > ? AND view_hash = ?", 
			noteID, clientIP, oneHourAgo, viewHash).First(&existingVisit).Error
		
		if err == nil {
			return nil
		}

		visit := models.NoteVisit{
			NoteID:    noteID,
			ViewerID:  &viewerID,
			VisitorIP: &clientIP,
			UserAgent: &userAgent,
			ViewHash:  &viewHash,
			VisitedAt: time.Now(),
		}

		if err := tx.Create(&visit).Error; err != nil {
			return err
		}

		return tx.Model(&note).Update("view_count", gorm.Expr("view_count + 1")).Error
	})
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

func (s *NoteService) GetPublicNoteByID(noteID uint, viewerInfo *models.ViewerInfo) (*models.Note, error) {
	var note models.Note
	err := s.db.Preload("Category").Preload("Tags").Preload("Attachments").
		Where("id = ? AND is_public = ?", noteID, true).First(&note).Error
	if err != nil {
		return nil, err
	}

	if viewerInfo != nil {
		go s.recordPublicView(noteID, viewerInfo)
	}

	return &note, nil
}

func (s *NoteService) recordPublicView(noteID uint, viewerInfo *models.ViewerInfo) {
	timeWindow := time.Now().Format("2006-01-02-15")
	identifier := fmt.Sprintf("%s-%d-%s", viewerInfo.IP, noteID, timeWindow)
	hash := fmt.Sprintf("%x", md5.Sum([]byte(identifier)))

	var existingVisit models.NoteVisit
	oneHourAgo := time.Now().Add(-1 * time.Hour)
	
	err := s.db.Where("note_id = ? AND visitor_ip = ? AND visited_at > ? AND view_hash = ?", 
		noteID, viewerInfo.IP, oneHourAgo, hash).First(&existingVisit).Error
	
	if err == nil {
		return
	}

	visit := models.NoteVisit{
		NoteID:    noteID,
		VisitorIP: &viewerInfo.IP,
		UserAgent: &viewerInfo.UserAgent,
		Referer:   &viewerInfo.Referer,
		ViewHash:  &hash,
		VisitedAt: time.Now(),
	}

	s.db.Create(&visit)
	s.db.Model(&models.Note{}).Where("id = ?", noteID).Update("view_count", gorm.Expr("view_count + 1"))
}