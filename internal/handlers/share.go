// internal/handlers/share.go - 完整修复版本
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"notes-backend/internal/models"
	"notes-backend/internal/services"
	"notes-backend/internal/utils"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
	"gorm.io/gorm"
)

type ShareHandler struct {
	db          *gorm.DB
	noteService *services.NoteService
	validator   *validator.Validate
}

func NewShareHandler(db *gorm.DB, noteService *services.NoteService) *ShareHandler {
	return &ShareHandler{
		db:          db,
		noteService: noteService,
		validator:   validator.New(),
	}
}

// CreateShareLink 创建分享链接
func (h *ShareHandler) CreateShareLink(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	var req models.ShareLinkCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// 如果没有请求体，使用默认空值
		req = models.ShareLinkCreateRequest{}
	}

	// 验证笔记是否存在且为公开笔记
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ? AND is_public = ?", noteID, userID, true).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.Error(c, http.StatusNotFound, "笔记不存在或非公开笔记")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 检查是否已存在活跃的分享链接
	var existingShare models.ShareLink
	if err := h.db.Where("note_id = ? AND is_active = ?", noteID, true).First(&existingShare).Error; err == nil {
		// 更新现有分享链接
		updates := models.ShareLink{
			Password:   req.Password,
			ExpireTime: req.ExpireTime,
		}

		if err := h.db.Model(&existingShare).Updates(updates).Error; err != nil {
			utils.InternalError(c)
			return
		}

		response := models.ShareLinkResponse{
			ShareCode:  existingShare.ShareCode,
			ShareURL:   fmt.Sprintf("http://localhost:9191/public/notes/%s", existingShare.ShareCode),
			Password:   req.Password,
			ExpireTime: req.ExpireTime,
		}

		utils.SuccessWithMessage(c, "分享链接更新成功", response)
		return
	}

	// 创建新的分享链接
	shareCode, err := generateRandomString(32)
	if err != nil {
		utils.InternalError(c)
		return
	}

	shareLink := models.ShareLink{
		NoteID:     uint(noteID),
		ShareCode:  shareCode,
		Password:   req.Password,
		ExpireTime: req.ExpireTime,
		VisitCount: 0,
		IsActive:   true,
	}

	if err := h.db.Create(&shareLink).Error; err != nil {
		utils.InternalError(c)
		return
	}

	response := models.ShareLinkResponse{
		ShareCode:  shareCode,
		ShareURL:   fmt.Sprintf("http://localhost:9191/public/notes/%s", shareCode),
		Password:   req.Password,
		ExpireTime: req.ExpireTime,
	}

	utils.SuccessWithMessage(c, "分享链接创建成功", response)
}

// GetShareInfo 获取分享信息
func (h *ShareHandler) GetShareInfo(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	// 验证笔记是否属于当前用户
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "笔记不存在")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 查找活跃的分享链接
	var shareLink models.ShareLink
	if err := h.db.Where("note_id = ? AND is_active = ?", noteID, true).First(&shareLink).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "分享链接不存在")
		} else {
			utils.InternalError(c)
		}
		return
	}

	response := models.ShareLinkResponse{
		ShareCode:  shareLink.ShareCode,
		ShareURL:   fmt.Sprintf("http://localhost:9191/public/notes/%s", shareLink.ShareCode),
		Password:   shareLink.Password,
		ExpireTime: shareLink.ExpireTime,
	}

	utils.Success(c, response)
}

// DeleteShareLink 删除分享链接
func (h *ShareHandler) DeleteShareLink(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	// 验证笔记是否属于当前用户
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "笔记不存在")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 软删除分享链接（设置为非活跃状态）
	result := h.db.Model(&models.ShareLink{}).Where("note_id = ? AND is_active = ?", noteID, true).Update("is_active", false)
	if result.Error != nil {
		utils.InternalError(c)
		return
	}

	if result.RowsAffected == 0 {
		utils.NotFound(c, "分享链接不存在")
		return
	}

	utils.SuccessWithMessage(c, "分享链接删除成功", nil)
}

// GetPublicNote 通过分享码获取公开笔记
func (h *ShareHandler) GetPublicNote(c *gin.Context) {
	shareCode := c.Param("code")

	var shareLink models.ShareLink
	if err := h.db.Preload("Note").Preload("Note.Category").Preload("Note.Tags").
		Where("share_code = ? AND is_active = ?", shareCode, true).First(&shareLink).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "分享链接不存在或已失效")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 检查分享链接是否过期
	if shareLink.ExpireTime != nil && time.Now().After(*shareLink.ExpireTime) {
		utils.Error(c, http.StatusGone, "分享链接已过期")
		return
	}

	// 检查访问密码
	password := c.Query("password")
	if shareLink.Password != nil && *shareLink.Password != "" {
		if password != *shareLink.Password {
			utils.Error(c, http.StatusUnauthorized, "访问密码错误")
			return
		}
	}

	// 准备访问者信息
	viewerInfo := &models.ViewerInfo{
		IP:        c.ClientIP(),
		UserAgent: c.GetHeader("User-Agent"),
		Referer:   c.GetHeader("Referer"),
	}

	// 获取笔记并记录浏览量
	note, err := h.noteService.GetPublicNoteByID(shareLink.NoteID, viewerInfo)
	if err != nil {
		utils.NotFound(c, "笔记不存在")
		return
	}

	// 异步更新分享链接访问次数
	go func() {
		h.db.Model(&shareLink).Update("visit_count", gorm.Expr("visit_count + 1"))
	}()

	utils.Success(c, note)
}

// generateRandomString 生成随机字符串
func generateRandomString(length int) (string, error) {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}