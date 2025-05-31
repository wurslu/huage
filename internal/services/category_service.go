package services

import (
	"fmt"
	"notes-backend/internal/models"

	"gorm.io/gorm"
)

type CategoryService struct {
	db *gorm.DB
}

func NewCategoryService(db *gorm.DB) *CategoryService {
	return &CategoryService{db: db}
}

func (s *CategoryService) GetCategoriesTree(userID uint) ([]models.Category, error) {
	var allCategories []models.Category
	
	err := s.db.Table("categories").
		Select("categories.*, COUNT(notes.id) as note_count").
		Joins("LEFT JOIN notes ON categories.id = notes.category_id AND notes.deleted_at IS NULL").
		Where("categories.user_id = ? AND categories.deleted_at IS NULL", userID).
		Group("categories.id").
		Order("categories.sort_order, categories.name").
		Find(&allCategories).Error
	
	if err != nil {
		return nil, err
	}

	// 构建树形结构
	categoryMap := make(map[uint]*models.Category)
	for i := range allCategories {
		allCategories[i].Children = []models.Category{}
		categoryMap[allCategories[i].ID] = &allCategories[i]
	}

	var rootCategories []models.Category
	for _, category := range allCategories {
		if category.ParentID == nil {
			rootCategories = append(rootCategories, category)
		} else {
			if parent, exists := categoryMap[*category.ParentID]; exists {
				parent.Children = append(parent.Children, category)
			}
		}
	}

	return rootCategories, nil
}

func (s *CategoryService) CreateCategory(userID uint, req *models.CategoryCreateRequest) (*models.Category, error) {
	// 检查父分类是否存在
	if req.ParentID != nil {
		var count int64
		if err := s.db.Model(&models.Category{}).Where("id = ? AND user_id = ?", *req.ParentID, userID).Count(&count).Error; err != nil {
			return nil, err
		}
		if count == 0 {
			return nil, fmt.Errorf("父分类不存在")
		}
	}

	// 检查同级分类名称是否重复
	var count int64
	query := s.db.Model(&models.Category{}).Where("user_id = ? AND name = ?", userID, req.Name)
	if req.ParentID == nil {
		query = query.Where("parent_id IS NULL")
	} else {
		query = query.Where("parent_id = ?", *req.ParentID)
	}
	
	if err := query.Count(&count).Error; err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, fmt.Errorf("同级分类名称已存在")
	}

	category := models.Category{
		UserID:      userID,
		Name:        req.Name,
		ParentID:    req.ParentID,
		Description: req.Description,
		SortOrder:   0,
	}

	if err := s.db.Create(&category).Error; err != nil {
		return nil, err
	}

	return &category, nil
}

func (s *CategoryService) UpdateCategory(categoryID, userID uint, req *models.CategoryCreateRequest) (*models.Category, error) {
	var category models.Category
	
	// 检查分类是否存在
	if err := s.db.Where("id = ? AND user_id = ?", categoryID, userID).First(&category).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("分类不存在")
		}
		return nil, err
	}

	// 检查不能设置为自己的子分类
	if req.ParentID != nil && *req.ParentID == categoryID {
		return nil, fmt.Errorf("不能将分类设置为自己的子分类")
	}

	// 更新分类
	updates := map[string]interface{}{
		"name":        req.Name,
		"parent_id":   req.ParentID,
		"description": req.Description,
	}
	
	if err := s.db.Model(&category).Updates(updates).Error; err != nil {
		return nil, err
	}

	return &category, nil
}

func (s *CategoryService) DeleteCategory(categoryID, userID uint) error {
	// 检查是否有子分类
	var count int64
	if err := s.db.Model(&models.Category{}).Where("parent_id = ?", categoryID).Count(&count).Error; err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("该分类下还有子分类，请先删除子分类")
	}

	// 检查是否有关联的笔记
	if err := s.db.Model(&models.Note{}).Where("category_id = ?", categoryID).Count(&count).Error; err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("该分类下还有笔记，请先移动或删除笔记")
	}

	// 删除分类
	result := s.db.Where("id = ? AND user_id = ?", categoryID, userID).Delete(&models.Category{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("分类不存在或无权限删除")
	}

	return nil
}
