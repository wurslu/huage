package services

import (
	"database/sql"
	"fmt"
	"math"
	"notes-backend/internal/models"
	"strings"

	"github.com/lib/pq"
)

type NoteService struct {
	db *sql.DB
}

func NewNoteService(db *sql.DB) *NoteService {
	return &NoteService{db: db}
}

func (s *NoteService) GetNotes(userID int, req *models.NoteListRequest) ([]models.Note, *models.Pagination, error) {
	// 构建查询条件
	var conditions []string
	var args []interface{}
	argIndex := 1

	conditions = append(conditions, fmt.Sprintf("n.user_id = $%d", argIndex))
	args = append(args, userID)
	argIndex++

	if req.CategoryID != nil {
		conditions = append(conditions, fmt.Sprintf("n.category_id = $%d", argIndex))
		args = append(args, *req.CategoryID)
		argIndex++
	}

	if req.Search != "" {
		conditions = append(conditions, fmt.Sprintf("(n.title ILIKE $%d OR n.content ILIKE $%d)", argIndex, argIndex))
		args = append(args, "%"+req.Search+"%")
		argIndex++
	}

	// 如果有标签筛选
	var tagJoin string
	if req.TagID != nil {
		tagJoin = "INNER JOIN note_tags nt ON n.id = nt.note_id"
		conditions = append(conditions, fmt.Sprintf("nt.tag_id = $%d", argIndex))
		args = append(args, *req.TagID)
		argIndex++
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	// 排序
	orderBy := "n.created_at DESC"
	if req.Sort != "" {
		direction := "DESC"
		if req.Order == "asc" {
			direction = "ASC"
		}
		orderBy = fmt.Sprintf("n.%s %s", req.Sort, direction)
	}

	// 计算总数
	countQuery := fmt.Sprintf(`
		SELECT COUNT(DISTINCT n.id)
		FROM notes n %s %s`,
		tagJoin, whereClause)

	var total int
	err := s.db.QueryRow(countQuery, args...).Scan(&total)
	if err != nil {
		return nil, nil, err
	}

	// 分页计算
	offset := (req.Page - 1) * req.Limit
	pages := int(math.Ceil(float64(total) / float64(req.Limit)))

	// 查询笔记列表
	query := fmt.Sprintf(`
		SELECT DISTINCT n.id, n.title, n.content, n.content_type, n.is_public, 
		       n.view_count, n.created_at, n.updated_at,
		       c.id, c.name
		FROM notes n
		LEFT JOIN categories c ON n.category_id = c.id
		%s %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d`,
		tagJoin, whereClause, orderBy, argIndex, argIndex+1)

	args = append(args, req.Limit, offset)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var notes []models.Note
	for rows.Next() {
		var note models.Note
		var categoryID sql.NullInt64
		var categoryName sql.NullString

		err := rows.Scan(
			&note.ID, &note.Title, &note.Content, &note.ContentType,
			&note.IsPublic, &note.ViewCount, &note.CreatedAt, &note.UpdatedAt,
			&categoryID, &categoryName)
		if err != nil {
			return nil, nil, err
		}

		if categoryID.Valid {
			note.Category = &models.Category{
				ID:   int(categoryID.Int64),
				Name: categoryName.String,
			}
		}

		notes = append(notes, note)
	}

	// 批量加载标签和附件
	if len(notes) > 0 {
		err = s.loadNotesTagsAndAttachments(notes)
		if err != nil {
			return nil, nil, err
		}
	}

	pagination := &models.Pagination{
		Page:  req.Page,
		Limit: req.Limit,
		Total: total,
		Pages: pages,
	}

	return notes, pagination, nil
}

func (s *NoteService) GetNoteByID(noteID, userID int) (*models.Note, error) {
	var note models.Note
	var categoryID sql.NullInt64
	var categoryName sql.NullString

	err := s.db.QueryRow(`
		SELECT n.id, n.user_id, n.title, n.content, n.content_type, 
		       n.is_public, n.view_count, n.created_at, n.updated_at,
		       c.id, c.name
		FROM notes n
		LEFT JOIN categories c ON n.category_id = c.id
		WHERE n.id = $1 AND n.user_id = $2`,
		noteID, userID).Scan(
		&note.ID, &note.UserID, &note.Title, &note.Content, &note.ContentType,
		&note.IsPublic, &note.ViewCount, &note.CreatedAt, &note.UpdatedAt,
		&categoryID, &categoryName)

	if err != nil {
		return nil, err
	}

	if categoryID.Valid {
		note.Category = &models.Category{
			ID:   int(categoryID.Int64),
			Name: categoryName.String,
		}
	}

	// 加载标签和附件
	err = s.loadNotesTagsAndAttachments([]models.Note{note})
	if err != nil {
		return nil, err
	}

	return &note, nil
}

func (s *NoteService) CreateNote(userID int, req *models.NoteCreateRequest) (*models.Note, error) {
	var note models.Note

	// 事务处理
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// 插入笔记
	err = tx.QueryRow(`
		INSERT INTO notes (user_id, category_id, title, content, content_type, is_public)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, user_id, category_id, title, content, content_type, is_public, view_count, created_at, updated_at`,
		userID, req.CategoryID, req.Title, req.Content, req.ContentType, req.IsPublic).Scan(
		&note.ID, &note.UserID, &note.CategoryID, &note.Title, &note.Content,
		&note.ContentType, &note.IsPublic, &note.ViewCount, &note.CreatedAt, &note.UpdatedAt)

	if err != nil {
		return nil, err
	}

	// 添加标签关联
	if len(req.TagIDs) > 0 {
		for _, tagID := range req.TagIDs {
			_, err = tx.Exec("INSERT INTO note_tags (note_id, tag_id) VALUES ($1, $2)", note.ID, tagID)
			if err != nil {
				return nil, err
			}
		}
	}

	if err = tx.Commit(); err != nil {
		return nil, err
	}

	return &note, nil
}

func (s *NoteService) UpdateNote(noteID, userID int, req *models.NoteUpdateRequest) (*models.Note, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// 更新笔记
	var note models.Note
	err = tx.QueryRow(`
		UPDATE notes 
		SET title = $1, content = $2, category_id = $3, is_public = $4, updated_at = CURRENT_TIMESTAMP
		WHERE id = $5 AND user_id = $6
		RETURNING id, user_id, category_id, title, content, content_type, is_public, view_count, created_at, updated_at`,
		req.Title, req.Content, req.CategoryID, req.IsPublic, noteID, userID).Scan(
		&note.ID, &note.UserID, &note.CategoryID, &note.Title, &note.Content,
		&note.ContentType, &note.IsPublic, &note.ViewCount, &note.CreatedAt, &note.UpdatedAt)

	if err != nil {
		return nil, err
	}

	// 更新标签关联
	_, err = tx.Exec("DELETE FROM note_tags WHERE note_id = $1", noteID)
	if err != nil {
		return nil, err
	}

	if len(req.TagIDs) > 0 {
		for _, tagID := range req.TagIDs {
			_, err = tx.Exec("INSERT INTO note_tags (note_id, tag_id) VALUES ($1, $2)", noteID, tagID)
			if err != nil {
				return nil, err
			}
		}
	}

	if err = tx.Commit(); err != nil {
		return nil, err
	}

	return &note, nil
}

func (s *NoteService) DeleteNote(noteID, userID int) error {
	result, err := s.db.Exec("DELETE FROM notes WHERE id = $1 AND user_id = $2", noteID, userID)
	if err != nil {
		return err
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rowsAffected == 0 {
		return fmt.Errorf("笔记不存在或无权限删除")
	}

	return nil
}

func (s *NoteService) loadNotesTagsAndAttachments(notes []models.Note) error {
	if len(notes) == 0 {
		return nil
	}

	noteIDs := make([]int, len(notes))
	noteMap := make(map[int]*models.Note)
	for i, note := range notes {
		noteIDs[i] = note.ID
		noteMap[note.ID] = &notes[i]
	}

	// 加载标签
	tagRows, err := s.db.Query(`
		SELECT nt.note_id, t.id, t.name, t.color
		FROM note_tags nt
		JOIN tags t ON nt.tag_id = t.id
		WHERE nt.note_id = ANY($1)`,
		pq.Array(noteIDs))
	if err != nil {
		return err
	}
	defer tagRows.Close()

	for tagRows.Next() {
		var noteID int
		var tag models.Tag
		err := tagRows.Scan(&noteID, &tag.ID, &tag.Name, &tag.Color)
		if err != nil {
			return err
		}

		if note, exists := noteMap[noteID]; exists {
			note.Tags = append(note.Tags, tag)
		}
	}

	// 加载附件
	attachmentRows, err := s.db.Query(`
		SELECT note_id, id, filename, original_filename, file_path, file_size, file_type, is_image
		FROM attachments
		WHERE note_id = ANY($1)`,
		pq.Array(noteIDs))
	if err != nil {
		return err
	}
	defer attachmentRows.Close()

	for attachmentRows.Next() {
		var noteID int
		var attachment models.Attachment
		err := attachmentRows.Scan(
			&noteID, &attachment.ID, &attachment.Filename, &attachment.OriginalFilename,
			&attachment.FilePath, &attachment.FileSize, &attachment.FileType, &attachment.IsImage)
		if err != nil {
			return err
		}

		if note, exists := noteMap[noteID]; exists {
			note.Attachments = append(note.Attachments, attachment)
		}
	}

	return nil
}

