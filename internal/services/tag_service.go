package services

import (
	"fmt"
	"notes-backend/internal/models"

	"gorm.io/gorm"
)

type TagService struct {
	db *gorm.DB
}

func NewTagService(db *gorm.DB) *TagService {
	return &TagService{db: db}
}

func (s *TagService) GetTags(userID uint) ([]models.Tag, error) {
	var tags []models.Tag
	
	err := s.db.Select("tags.*, COUNT(note_tags.note_id) as note_count").
		Joins("LEFT JOIN note_tags ON tags.id = note_tags.tag_id").
		Where("tags.user_id = ?", userID).
		Group("tags.id").
		Order("tags.name").
		Find(&tags).Error
	
	if err != nil {
		return nil, err
	}

	return tags, nil
}

func (s *TagService) CreateTag(userID uint, req *models.TagCreateRequest) (*models.Tag, error) {
	// 检查标签名称是否已存在
	var count int64
	if err := s.db.Model(&models.Tag{}).Where("user_id = ? AND name = ?", userID, req.Name).Count(&count).Error; err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, fmt.Errorf("标签名称已存在")
	}

	tag := models.Tag{
		UserID: userID,
		Name:   req.Name,
		Color:  req.Color,
	}

	if err := s.db.Create(&tag).Error; err != nil {
		return nil, err
	}

	return &tag, nil
}

func (s *TagService) UpdateTag(tagID, userID uint, req *models.TagCreateRequest) (*models.Tag, error) {
	var tag models.Tag
	
	result := s.db.Model(&tag).Where("id = ? AND user_id = ?", tagID, userID).Updates(map[string]interface{}{
		"name":  req.Name,
		"color": req.Color,
	})
	
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected == 0 {
		return nil, fmt.Errorf("标签不存在")
	}

	// 重新获取更新后的标签
	if err := s.db.Where("id = ?", tagID).First(&tag).Error; err != nil {
		return nil, err
	}

	return &tag, nil
}

func (s *TagService) DeleteTag(tagID, userID uint) error {
	result := s.db.Where("id = ? AND user_id = ?", tagID, userID).Delete(&models.Tag{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("标签不存在或无权限删除")
	}
	return nil
}
