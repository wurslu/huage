package services

import (
	"fmt"
	"io"
	"mime/multipart"
	"notes-backend/internal/models"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type FileService struct {
	db         *gorm.DB
	uploadPath string
	maxStorage int64
}

func NewFileService(db *gorm.DB, uploadPath string, maxStorage int64) *FileService {
	return &FileService{
		db:         db,
		uploadPath: uploadPath,
		maxStorage: maxStorage,
	}
}

func (s *FileService) UploadFile(noteID, userID uint, file multipart.File, header *multipart.FileHeader) (*models.Attachment, error) {
	var note models.Note
	if err := s.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		return nil, fmt.Errorf("笔记不存在或无权限")
	}

	ext := filepath.Ext(header.Filename)
	newFileName := uuid.New().String() + ext
	
	userDir := filepath.Join(s.uploadPath, "users", fmt.Sprintf("%d", userID))
	if err := os.MkdirAll(userDir, 0755); err != nil {
		return nil, fmt.Errorf("创建目录失败: %v", err)
	}

	filePath := filepath.Join(userDir, newFileName)
	dst, err := os.Create(filePath)
	if err != nil {
		return nil, fmt.Errorf("创建文件失败: %v", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		return nil, fmt.Errorf("保存文件失败: %v", err)
	}

	ext = strings.ToLower(strings.TrimPrefix(ext, "."))
	isImage := s.isImageType(ext)

	contentType := header.Header.Get("Content-Type")

	attachment := models.Attachment{
		NoteID:           noteID,
		Filename:         newFileName,
		OriginalFilename: header.Filename,
		FilePath:         filePath,
		FileSize:         header.Size,
		FileType:         ext,
		MimeType:         &contentType,
		IsImage:          isImage,
	}

	if err := s.db.Create(&attachment).Error; err != nil {
		os.Remove(filePath)
		return nil, fmt.Errorf("保存附件记录失败: %v", err)
	}

	s.updateUserStorage(userID, header.Size, isImage)

	attachment.URLs = &models.FileURLs{
		Original: fmt.Sprintf("/api/files/%d", attachment.ID),
	}

	return &attachment, nil
}

func (s *FileService) GetAttachments(noteID, userID uint) ([]models.Attachment, error) {
	var attachments []models.Attachment
	
	err := s.db.Joins("JOIN notes ON attachments.note_id = notes.id").
		Where("attachments.note_id = ? AND notes.user_id = ?", noteID, userID).
		Find(&attachments).Error
	
	if err != nil {
		return nil, err
	}

	for i := range attachments {
		attachments[i].URLs = &models.FileURLs{
			Original: fmt.Sprintf("/api/files/%d", attachments[i].ID),
		}
	}

	return attachments, nil
}

func (s *FileService) DeleteAttachment(attachmentID, userID uint) error {
	var attachment models.Attachment
	
	err := s.db.Joins("JOIN notes ON attachments.note_id = notes.id").
		Where("attachments.id = ? AND notes.user_id = ?", attachmentID, userID).
		First(&attachment).Error
	
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return fmt.Errorf("附件不存在或无权限删除")
		}
		return err
	}

	if err := os.Remove(attachment.FilePath); err != nil {
		fmt.Printf("Failed to delete file: %v\n", err)
	}

	if err := s.db.Delete(&attachment).Error; err != nil {
		return err
	}

	s.updateUserStorage(userID, -attachment.FileSize, attachment.IsImage)

	return nil
}

func (s *FileService) CheckUserStorage(userID uint, fileSize int64) (bool, error) {
	var storage models.UserStorage
	
	if err := s.db.Where("user_id = ?", userID).First(&storage).Error; err != nil {
		return false, err
	}

	return storage.UsedSpace+fileSize <= s.maxStorage, nil
}

func (s *FileService) GetUserStorageInfo(userID uint) (*models.UserStorage, error) {
	var storage models.UserStorage
	
	if err := s.db.Where("user_id = ?", userID).First(&storage).Error; err != nil {
		return nil, err
	}

	return &storage, nil
}

func (s *FileService) updateUserStorage(userID uint, sizeChange int64, isImage bool) {
	updates := map[string]interface{}{
		"used_space": gorm.Expr("used_space + ?", sizeChange),
		"updated_at": time.Now(),
	}

	if sizeChange > 0 {
		updates["file_count"] = gorm.Expr("file_count + 1")
		if isImage {
			updates["image_count"] = gorm.Expr("image_count + 1")
		} else {
			updates["document_count"] = gorm.Expr("document_count + 1")
		}
	} else {
		updates["file_count"] = gorm.Expr("file_count - 1")
		if isImage {
			updates["image_count"] = gorm.Expr("image_count - 1")
		} else {
			updates["document_count"] = gorm.Expr("document_count - 1")
		}
	}

	s.db.Model(&models.UserStorage{}).Where("user_id = ?", userID).Updates(updates)
}

func (s *FileService) isImageType(ext string) bool {
	imageTypes := []string{"jpg", "jpeg", "png", "gif", "webp"}
	for _, t := range imageTypes {
		if ext == t {
			return true
		}
	}
	return false
}

func (s *FileService) GetAttachmentByID(attachmentID, userID uint) (*models.Attachment, error) {
	var attachment models.Attachment
	
	err := s.db.Joins("JOIN notes ON attachments.note_id = notes.id").
		Where("attachments.id = ? AND notes.user_id = ?", attachmentID, userID).
		First(&attachment).Error
	
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("附件不存在或无权限访问")
		}
		return nil, err
	}

	attachment.URLs = &models.FileURLs{
		Original: fmt.Sprintf("/api/files/%d", attachment.ID),
	}

	return &attachment, nil
}

