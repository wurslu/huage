// internal/services/file_service.go - 修复为软删除
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

// 修复：软删除附件
func (s *FileService) DeleteAttachment(attachmentID, userID uint) error {
	fmt.Printf("FileService.DeleteAttachment called: attachmentID=%d, userID=%d\n", attachmentID, userID)

	return s.db.Transaction(func(tx *gorm.DB) error {
		var attachment models.Attachment
		
		// 修复：查询时需要包含软删除的记录验证
		err := tx.Unscoped().Table("attachments").
			Select("attachments.*").
			Joins("JOIN notes ON attachments.note_id = notes.id").
			Where("attachments.id = ? AND notes.user_id = ? AND attachments.deleted_at IS NULL", attachmentID, userID).
			First(&attachment).Error
		
		if err != nil {
			if err == gorm.ErrRecordNotFound {
				fmt.Printf("Attachment not found or permission denied: attachmentID=%d, userID=%d\n", attachmentID, userID)
				return fmt.Errorf("附件不存在或无权限删除")
			}
			fmt.Printf("Database error when finding attachment: %v\n", err)
			return err
		}

		fmt.Printf("Found attachment to delete: %+v\n", attachment)

		// 记录要更新的存储信息
		fileSize := attachment.FileSize
		isImage := attachment.IsImage

		// 修复：使用软删除而不是硬删除
		result := tx.Delete(&attachment)
		if result.Error != nil {
			fmt.Printf("Failed to soft delete attachment: %v\n", result.Error)
			return result.Error
		}

		if result.RowsAffected == 0 {
			fmt.Printf("No rows affected when soft deleting attachment: attachmentID=%d\n", attachmentID)
			return fmt.Errorf("附件删除失败，未找到记录")
		}

		fmt.Printf("Attachment soft deleted, rows affected: %d\n", result.RowsAffected)

		// 更新用户存储统计（减少使用量）
		if err := s.updateUserStorageInTx(tx, userID, -fileSize, isImage); err != nil {
			fmt.Printf("Failed to update user storage: %v\n", err)
			return err
		}

		fmt.Printf("User storage updated successfully after soft deleting attachment\n")
		
		// 注意：软删除时我们不删除物理文件，以防需要恢复
		// 如果需要定期清理物理文件，可以创建一个定时任务来处理真正删除的文件
		fmt.Printf("Physical file kept for potential recovery: %s\n", attachment.FilePath)
		
		return nil
	})
}

// 新增：彻底删除附件（包括物理文件）- 用于定期清理任务
func (s *FileService) PermanentlyDeleteAttachment(attachmentID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var attachment models.Attachment
		
		// 查找已软删除的附件
		err := tx.Unscoped().Where("id = ? AND deleted_at IS NOT NULL", attachmentID).First(&attachment).Error
		if err != nil {
			return err
		}

		// 删除物理文件
		if err := os.Remove(attachment.FilePath); err != nil {
			fmt.Printf("Warning: Failed to delete physical file %s: %v\n", attachment.FilePath, err)
		}

		// 硬删除数据库记录
		return tx.Unscoped().Delete(&attachment).Error
	})
}

// 新增：恢复软删除的附件
func (s *FileService) RestoreAttachment(attachmentID, userID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		var attachment models.Attachment
		
		// 查找软删除的附件
		err := tx.Unscoped().Table("attachments").
			Select("attachments.*").
			Joins("JOIN notes ON attachments.note_id = notes.id").
			Where("attachments.id = ? AND notes.user_id = ? AND attachments.deleted_at IS NOT NULL", attachmentID, userID).
			First(&attachment).Error
		
		if err != nil {
			return fmt.Errorf("附件不存在或无权限恢复")
		}

		// 恢复附件
		result := tx.Unscoped().Model(&attachment).Update("deleted_at", nil)
		if result.Error != nil {
			return result.Error
		}

		// 恢复存储统计
		return s.updateUserStorageInTx(tx, userID, attachment.FileSize, attachment.IsImage)
	})
}

// 修复：获取附件时排除软删除的记录
func (s *FileService) GetAttachments(noteID, userID uint) ([]models.Attachment, error) {
	var attachments []models.Attachment
	
	// 修复：默认不查询软删除的附件
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

// 修复：获取单个附件时排除软删除的记录
func (s *FileService) GetAttachmentByID(attachmentID, userID uint) (*models.Attachment, error) {
	var attachment models.Attachment
	
	// 修复：默认不查询软删除的附件
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

// 修复：检查用户存储时排除软删除的附件
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

// 修复：重新计算用户存储统计（排除软删除的附件）
func (s *FileService) RecalculateUserStorage(userID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// 计算实际的存储使用情况（排除软删除的附件）
		var totalSize int64
		var fileCount, imageCount, documentCount int64

		// 查询该用户所有未软删除的附件
		var attachments []models.Attachment
		err := tx.Joins("JOIN notes ON attachments.note_id = notes.id").
			Where("notes.user_id = ?", userID).
			Find(&attachments).Error
		
		if err != nil {
			return err
		}

		// 计算统计数据
		for _, attachment := range attachments {
			totalSize += attachment.FileSize
			fileCount++
			if attachment.IsImage {
				imageCount++
			} else {
				documentCount++
			}
		}

		// 更新或创建存储记录
		storage := models.UserStorage{
			UserID:        userID,
			UsedSpace:     totalSize,
			FileCount:     int(fileCount),
			ImageCount:    int(imageCount),
			DocumentCount: int(documentCount),
		}

		return tx.Model(&models.UserStorage{}).Where("user_id = ?", userID).Updates(&storage).Error
	})
}

// 在事务中更新存储统计的方法
func (s *FileService) updateUserStorageInTx(tx *gorm.DB, userID uint, sizeChange int64, isImage bool) error {
	fmt.Printf("updateUserStorageInTx: userID=%d, sizeChange=%d, isImage=%v\n", userID, sizeChange, isImage)

	var storage models.UserStorage
	
	// 获取当前存储记录
	if err := tx.Where("user_id = ?", userID).First(&storage).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			fmt.Printf("User storage record not found, creating new one for userID=%d\n", userID)
			storage = models.UserStorage{
				UserID:        userID,
				UsedSpace:     0,
				FileCount:     0,
				ImageCount:    0,
				DocumentCount: 0,
			}
			if err := tx.Create(&storage).Error; err != nil {
				fmt.Printf("Failed to create user storage record: %v\n", err)
				return err
			}
		} else {
			fmt.Printf("Failed to get user storage record: %v\n", err)
			return err
		}
	}

	fmt.Printf("Current storage before update: %+v\n", storage)

	// 计算新的存储使用量，确保不会变成负数
	newUsedSpace := storage.UsedSpace + sizeChange
	if newUsedSpace < 0 {
		newUsedSpace = 0
	}

	// 准备更新数据
	updates := map[string]interface{}{
		"used_space": newUsedSpace,
		"updated_at": time.Now(),
	}

	// 更新文件计数
	if sizeChange > 0 {
		// 添加文件
		updates["file_count"] = gorm.Expr("file_count + 1")
		if isImage {
			updates["image_count"] = gorm.Expr("image_count + 1")
		} else {
			updates["document_count"] = gorm.Expr("document_count + 1")
		}
	} else {
		// 删除文件 - 确保计数不会变成负数
		updates["file_count"] = gorm.Expr("GREATEST(file_count - 1, 0)")
		if isImage {
			updates["image_count"] = gorm.Expr("GREATEST(image_count - 1, 0)")
		} else {
			updates["document_count"] = gorm.Expr("GREATEST(document_count - 1, 0)")
		}
	}

	fmt.Printf("Updates to apply: %+v\n", updates)

	// 执行更新
	result := tx.Model(&storage).Where("user_id = ?", userID).Updates(updates)
	if result.Error != nil {
		fmt.Printf("Failed to update user storage: %v\n", result.Error)
		return result.Error
	}

	fmt.Printf("Storage updated successfully, rows affected: %d\n", result.RowsAffected)
	return nil
}

// 保持原有的方法兼容性
func (s *FileService) updateUserStorage(userID uint, sizeChange int64, isImage bool) {
	err := s.db.Transaction(func(tx *gorm.DB) error {
		return s.updateUserStorageInTx(tx, userID, sizeChange, isImage)
	})

	if err != nil {
		fmt.Printf("Failed to update user storage: %v\n", err)
	} else {
		fmt.Printf("Updated user storage: userID=%d, sizeChange=%d, isImage=%v\n", userID, sizeChange, isImage)
	}
}

// 其他方法保持不变...
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

func (s *FileService) isImageType(ext string) bool {
	imageTypes := []string{"jpg", "jpeg", "png", "gif", "webp"}
	for _, t := range imageTypes {
		if ext == t {
			return true
		}
	}
	return false
}