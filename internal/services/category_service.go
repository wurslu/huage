// internal/services/category_service.go
package services

import (
	"database/sql"
	"fmt"
	"notes-backend/internal/models"
)

type CategoryService struct {
	db *sql.DB
}

func NewCategoryService(db *sql.DB) *CategoryService {
	return &CategoryService{db: db}
}

func (s *CategoryService) GetCategoriesTree(userID int) ([]models.Category, error) {
	// 获取所有分类
	rows, err := s.db.Query(`
		SELECT c.id, c.name, c.parent_id, c.sort_order, c.description, c.created_at, c.updated_at,
		       COUNT(n.id) as note_count
		FROM categories c
		LEFT JOIN notes n ON c.id = n.category_id
		WHERE c.user_id = $1
		GROUP BY c.id, c.name, c.parent_id, c.sort_order, c.description, c.created_at, c.updated_at
		ORDER BY c.sort_order, c.name`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var allCategories []models.Category
	categoryMap := make(map[int]*models.Category)

	for rows.Next() {
		var category models.Category
		err := rows.Scan(
			&category.ID, &category.Name, &category.ParentID, &category.SortOrder,
			&category.Description, &category.CreatedAt, &category.UpdatedAt, &category.NoteCount)
		if err != nil {
			return nil, err
		}

		category.UserID = userID
		category.Children = make([]models.Category, 0)
		allCategories = append(allCategories, category)
		categoryMap[category.ID] = &allCategories[len(allCategories)-1]
	}

	// 构建树形结构
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

func (s *CategoryService) CreateCategory(userID int, req *models.CategoryCreateRequest) (*models.Category, error) {
	// 检查父分类是否存在且属于当前用户
	if req.ParentID != nil {
		var exists bool
		err := s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM categories WHERE id = $1 AND user_id = $2)",
			*req.ParentID, userID).Scan(&exists)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, fmt.Errorf("父分类不存在")
		}
	}

	// 检查同级分类名称是否重复
	var exists bool
	if req.ParentID == nil {
		err := s.db.QueryRow(`
			SELECT EXISTS(SELECT 1 FROM categories 
			WHERE user_id = $1 AND name = $2 AND parent_id IS NULL)`,
			userID, req.Name).Scan(&exists)
		if err != nil {
			return nil, err
		}
	} else {
		err := s.db.QueryRow(`
			SELECT EXISTS(SELECT 1 FROM categories 
			WHERE user_id = $1 AND name = $2 AND parent_id = $3)`,
			userID, req.Name, *req.ParentID).Scan(&exists)
		if err != nil {
			return nil, err
		}
	}

	if exists {
		return nil, fmt.Errorf("同级分类名称已存在")
	}

	var category models.Category
	err := s.db.QueryRow(`
		INSERT INTO categories (user_id, name, parent_id, description, sort_order)
		VALUES ($1, $2, $3, $4, 0)
		RETURNING id, user_id, name, parent_id, sort_order, description, created_at, updated_at`,
		userID, req.Name, req.ParentID, req.Description).Scan(
		&category.ID, &category.UserID, &category.Name, &category.ParentID,
		&category.SortOrder, &category.Description, &category.CreatedAt, &category.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return &category, nil
}

func (s *CategoryService) UpdateCategory(categoryID, userID int, req *models.CategoryCreateRequest) (*models.Category, error) {
	// 检查分类是否存在且属于当前用户
	var exists bool
	err := s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM categories WHERE id = $1 AND user_id = $2)",
		categoryID, userID).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, fmt.Errorf("分类不存在")
	}

	// 如果更改了父分类，检查不能设置为自己的子分类
	if req.ParentID != nil && *req.ParentID == categoryID {
		return nil, fmt.Errorf("不能将分类设置为自己的子分类")
	}

	var category models.Category
	err = s.db.QueryRow(`
		UPDATE categories 
		SET name = $1, parent_id = $2, description = $3, updated_at = CURRENT_TIMESTAMP
		WHERE id = $4 AND user_id = $5
		RETURNING id, user_id, name, parent_id, sort_order, description, created_at, updated_at`,
		req.Name, req.ParentID, req.Description, categoryID, userID).Scan(
		&category.ID, &category.UserID, &category.Name, &category.ParentID,
		&category.SortOrder, &category.Description, &category.CreatedAt, &category.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return &category, nil
}

func (s *CategoryService) DeleteCategory(categoryID, userID int) error {
	// 检查是否有子分类
	var hasChildren bool
	err := s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM categories WHERE parent_id = $1)", categoryID).Scan(&hasChildren)
	if err != nil {
		return err
	}
	if hasChildren {
		return fmt.Errorf("该分类下还有子分类，请先删除子分类")
	}

	// 检查是否有关联的笔记
	var hasNotes bool
	err = s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM notes WHERE category_id = $1)", categoryID).Scan(&hasNotes)
	if err != nil {
		return err
	}
	if hasNotes {
		return fmt.Errorf("该分类下还有笔记，请先移动或删除笔记")
	}

	// 删除分类
	result, err := s.db.Exec("DELETE FROM categories WHERE id = $1 AND user_id = $2", categoryID, userID)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return fmt.Errorf("分类不存在或无权限删除")
	}

	return nil
}

// internal/services/tag_service.go
type TagService struct {
	db *sql.DB
}

func NewTagService(db *sql.DB) *TagService {
	return &TagService{db: db}
}

func (s *TagService) GetTags(userID int) ([]models.Tag, error) {
	rows, err := s.db.Query(`
		SELECT t.id, t.name, t.color, t.created_at, COUNT(nt.note_id) as note_count
		FROM tags t
		LEFT JOIN note_tags nt ON t.id = nt.tag_id
		WHERE t.user_id = $1
		GROUP BY t.id, t.name, t.color, t.created_at
		ORDER BY t.name`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tags []models.Tag
	for rows.Next() {
		var tag models.Tag
		err := rows.Scan(&tag.ID, &tag.Name, &tag.Color, &tag.CreatedAt, &tag.NoteCount)
		if err != nil {
			return nil, err
		}
		tag.UserID = userID
		tags = append(tags, tag)
	}

	return tags, nil
}

func (s *TagService) CreateTag(userID int, req *models.TagCreateRequest) (*models.Tag, error) {
	// 检查标签名称是否已存在
	var exists bool
	err := s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM tags WHERE user_id = $1 AND name = $2)",
		userID, req.Name).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, fmt.Errorf("标签名称已存在")
	}

	var tag models.Tag
	err = s.db.QueryRow(`
		INSERT INTO tags (user_id, name, color)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, color, created_at`,
		userID, req.Name, req.Color).Scan(
		&tag.ID, &tag.UserID, &tag.Name, &tag.Color, &tag.CreatedAt)

	if err != nil {
		return nil, err
	}

	return &tag, nil
}

func (s *TagService) UpdateTag(tagID, userID int, req *models.TagCreateRequest) (*models.Tag, error) {
	var tag models.Tag
	err := s.db.QueryRow(`
		UPDATE tags 
		SET name = $1, color = $2
		WHERE id = $3 AND user_id = $4
		RETURNING id, user_id, name, color, created_at`,
		req.Name, req.Color, tagID, userID).Scan(
		&tag.ID, &tag.UserID, &tag.Name, &tag.Color, &tag.CreatedAt)

	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("标签不存在")
	}
	if err != nil {
		return nil, err
	}

	return &tag, nil
}

func (s *TagService) DeleteTag(tagID, userID int) error {
	result, err := s.db.Exec("DELETE FROM tags WHERE id = $1 AND user_id = $2", tagID, userID)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return fmt.Errorf("标签不存在或无权限删除")
	}

	return nil
}

