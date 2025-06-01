// internal/services/tag_service.go - 修复版本
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

// TagWithCount 用于接收联表查询结果
type TagWithCount struct {
	models.Tag
	NoteCount int `gorm:"column:note_count"`
}

func (s *TagService) GetTags(userID uint) ([]models.Tag, error) {
	var tagsWithCount []TagWithCount
	
	// 使用联表查询计算每个标签的笔记数量
	err := s.db.Table("tags").
		Select("tags.*, COALESCE(COUNT(DISTINCT note_tags.note_id), 0) as note_count").
		Joins("LEFT JOIN note_tags ON tags.id = note_tags.tag_id").
		Joins("LEFT JOIN notes ON note_tags.note_id = notes.id AND notes.deleted_at IS NULL").
		Where("tags.user_id = ? AND tags.deleted_at IS NULL", userID).
		Group("tags.id, tags.user_id, tags.name, tags.color, tags.created_at, tags.deleted_at").
		Order("tags.name").
		Find(&tagsWithCount).Error
	
	if err != nil {
		return nil, err
	}

	// 转换为普通的Tag切片，并设置NoteCount字段
	var tags []models.Tag
	for _, tagWithCount := range tagsWithCount {
		tag := tagWithCount.Tag
		tag.NoteCount = tagWithCount.NoteCount
		tags = append(tags, tag)
	}

	return tags, nil
}

func (s *TagService) CreateTag(userID uint, req *models.TagCreateRequest) (*models.Tag, error) {
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

	// 设置初始笔记数量为0
	tag.NoteCount = 0

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

	// 重新获取更新后的标签，包含笔记数量
	var tagWithCount TagWithCount
	err := s.db.Table("tags").
		Select("tags.*, COALESCE(COUNT(DISTINCT note_tags.note_id), 0) as note_count").
		Joins("LEFT JOIN note_tags ON tags.id = note_tags.tag_id").
		Joins("LEFT JOIN notes ON note_tags.note_id = notes.id AND notes.deleted_at IS NULL").
		Where("tags.id = ?", tagID).
		Group("tags.id, tags.user_id, tags.name, tags.color, tags.created_at, tags.deleted_at").
		First(&tagWithCount).Error

	if err != nil {
		return nil, err
	}

	updatedTag := tagWithCount.Tag
	updatedTag.NoteCount = tagWithCount.NoteCount

	return &updatedTag, nil
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