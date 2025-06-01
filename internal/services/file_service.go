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

// UploadFile 上传文件
func (s *FileService) UploadFile(noteID, userID uint, file multipart.File, header *multipart.FileHeader) (*models.Attachment, error) {
	// 验证笔记是否属于用户
	var note models.Note
	if err := s.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		return nil, fmt.Errorf("笔记不存在或无权限")
	}

	// 生成唯一文件名
	ext := filepath.Ext(header.Filename)
	newFileName := uuid.New().String() + ext
	
	// 创建用户目录
	userDir := filepath.Join(s.uploadPath, "users", fmt.Sprintf("%d", userID))
	if err := os.MkdirAll(userDir, 0755); err != nil {
		return nil, fmt.Errorf("创建目录失败: %v", err)
	}

	// 保存文件
	filePath := filepath.Join(userDir, newFileName)
	dst, err := os.Create(filePath)
	if err != nil {
		return nil, fmt.Errorf("创建文件失败: %v", err)
	}
	defer dst.Close()

	// 复制文件内容
	if _, err := io.Copy(dst, file); err != nil {
		return nil, fmt.Errorf("保存文件失败: %v", err)
	}

	// 确定文件类型
	ext = strings.ToLower(strings.TrimPrefix(ext, "."))
	isImage := s.isImageType(ext)

	// 获取Content-Type
	contentType := header.Header.Get("Content-Type")

	// 创建附件记录
	attachment := models.Attachment{
		NoteID:           noteID,
		Filename:         newFileName,
		OriginalFilename: header.Filename,
		FilePath:         filePath,
		FileSize:         header.Size,
		FileType:         ext,
		MimeType:         &contentType, // 修复：不取地址
		IsImage:          isImage,
	}

	if err := s.db.Create(&attachment).Error; err != nil {
		// 删除已上传的文件
		os.Remove(filePath)
		return nil, fmt.Errorf("保存附件记录失败: %v", err)
	}

	// 更新用户存储统计
	s.updateUserStorage(userID, header.Size, isImage)

	// 设置文件URL
	attachment.URLs = &models.FileURLs{
		Original: fmt.Sprintf("/uploads/users/%d/%s", userID, newFileName),
	}

	return &attachment, nil
}

// GetAttachments 获取笔记的附件列表
func (s *FileService) GetAttachments(noteID, userID uint) ([]models.Attachment, error) {
	var attachments []models.Attachment
	
	err := s.db.Joins("JOIN notes ON attachments.note_id = notes.id").
		Where("attachments.note_id = ? AND notes.user_id = ?", noteID, userID).
		Find(&attachments).Error
	
	if err != nil {
		return nil, err
	}

	// 设置文件URLs
	for i := range attachments {
		attachments[i].URLs = &models.FileURLs{
			Original: fmt.Sprintf("/uploads/users/%d/%s", userID, attachments[i].Filename),
		}
	}

	return attachments, nil
}

// DeleteAttachment 删除附件
func (s *FileService) DeleteAttachment(attachmentID, userID uint) error {
	var attachment models.Attachment
	
	// 查找附件并验证权限
	err := s.db.Joins("JOIN notes ON attachments.note_id = notes.id").
		Where("attachments.id = ? AND notes.user_id = ?", attachmentID, userID).
		First(&attachment).Error
	
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return fmt.Errorf("附件不存在或无权限删除")
		}
		return err
	}

	// 删除物理文件
	if err := os.Remove(attachment.FilePath); err != nil {
		// 记录错误但不阻止删除数据库记录
		fmt.Printf("Failed to delete file: %v\n", err)
	}

	// 删除数据库记录
	if err := s.db.Delete(&attachment).Error; err != nil {
		return err
	}

	// 更新用户存储统计
	s.updateUserStorage(userID, -attachment.FileSize, attachment.IsImage)

	return nil
}

// CheckUserStorage 检查用户存储空间
func (s *FileService) CheckUserStorage(userID uint, fileSize int64) (bool, error) {
	var storage models.UserStorage
	
	if err := s.db.Where("user_id = ?", userID).First(&storage).Error; err != nil {
		return false, err
	}

	return storage.UsedSpace+fileSize <= s.maxStorage, nil
}

// GetUserStorageInfo 获取用户存储信息
func (s *FileService) GetUserStorageInfo(userID uint) (*models.UserStorage, error) {
	var storage models.UserStorage
	
	if err := s.db.Where("user_id = ?", userID).First(&storage).Error; err != nil {
		return nil, err
	}

	return &storage, nil
}

// updateUserStorage 更新用户存储统计
func (s *FileService) updateUserStorage(userID uint, sizeChange int64, isImage bool) {
	updates := map[string]interface{}{
		"used_space": gorm.Expr("used_space + ?", sizeChange),
		"updated_at": time.Now(),
	}

	if sizeChange > 0 { // 上传文件
		updates["file_count"] = gorm.Expr("file_count + 1")
		if isImage {
			updates["image_count"] = gorm.Expr("image_count + 1")
		} else {
			updates["document_count"] = gorm.Expr("document_count + 1")
		}
	} else { // 删除文件
		updates["file_count"] = gorm.Expr("file_count - 1")
		if isImage {
			updates["image_count"] = gorm.Expr("image_count - 1")
		} else {
			updates["document_count"] = gorm.Expr("document_count - 1")
		}
	}

	s.db.Model(&models.UserStorage{}).Where("user_id = ?", userID).Updates(updates)
}

// isImageType 检查是否为图片类型
func (s *FileService) isImageType(ext string) bool {
	imageTypes := []string{"jpg", "jpeg", "png", "gif", "webp"}
	for _, t := range imageTypes {
		if ext == t {
			return true
		}
	}
	return false
}