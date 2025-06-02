package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"notes-backend/internal/config"
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
	config      *config.Config
}

func NewShareHandler(db *gorm.DB, noteService *services.NoteService, cfg *config.Config) *ShareHandler {
	return &ShareHandler{
		db:          db,
		noteService: noteService,
		validator:   validator.New(),
		config:      cfg,
	}
}

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
		req = models.ShareLinkCreateRequest{}
	}

	// 检查笔记是否存在且为公开笔记
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ? AND is_public = ?", noteID, userID, true).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.Error(c, http.StatusNotFound, "笔记不存在或非公开笔记")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 检查是否已有分享链接
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
			// 修复：使用新的路径 /shared/
			ShareURL:   fmt.Sprintf("%s/shared/%s", h.config.Frontend.BaseURL, existingShare.ShareCode),
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
		// 修复：使用新的路径 /shared/，移除多余的 notes
		ShareURL:   fmt.Sprintf("%s/shared/%s", h.config.Frontend.BaseURL, shareCode),
		Password:   req.Password,
		ExpireTime: req.ExpireTime,
	}

	utils.SuccessWithMessage(c, "分享链接创建成功", response)
}

func (h *ShareHandler) GetShareInfo(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	// 检查笔记是否存在
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "笔记不存在")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 获取分享链接
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
		// 修复：使用新的路径 /shared/
		ShareURL:   fmt.Sprintf("%s/shared/%s", h.config.Frontend.BaseURL, shareLink.ShareCode),
		Password:   shareLink.Password,
		ExpireTime: shareLink.ExpireTime,
	}

	utils.Success(c, response)
}

func (h *ShareHandler) DeleteShareLink(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	// 检查笔记是否存在
	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.NotFound(c, "笔记不存在")
		} else {
			utils.InternalError(c)
		}
		return
	}

	// 删除分享链接（软删除）
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

func (h *ShareHandler) GetPublicNote(c *gin.Context) {
	shareCode := c.Param("code")
	
	fmt.Printf("GetPublicNote called with code: %s\n", shareCode)
	fmt.Printf("Request path: %s\n", c.Request.URL.Path)
	fmt.Printf("Request method: %s\n", c.Request.Method)

	// 查找分享链接
	var shareLink models.ShareLink
	if err := h.db.Preload("Note").Preload("Note.Category").Preload("Note.Tags").
		Where("share_code = ? AND is_active = ?", shareCode, true).First(&shareLink).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			fmt.Printf("Share link not found for code: %s\n", shareCode)
			utils.NotFound(c, "分享链接不存在或已失效")
		} else {
			fmt.Printf("Database error: %v\n", err)
			utils.InternalError(c)
		}
		return
	}

	fmt.Printf("Found share link: %+v\n", shareLink)

	// 检查是否过期
	if shareLink.ExpireTime != nil && time.Now().After(*shareLink.ExpireTime) {
		fmt.Printf("Share link expired: %v\n", *shareLink.ExpireTime)
		utils.Error(c, http.StatusGone, "分享链接已过期")
		return
	}

	// 检查密码
	password := c.Query("password")
	if shareLink.Password != nil && *shareLink.Password != "" {
		fmt.Printf("Password required. Provided: %v, Expected: %v\n", password, *shareLink.Password)
		if password != *shareLink.Password {
			utils.Error(c, http.StatusUnauthorized, "访问密码错误")
			return
		}
	}

	// 获取笔记详情
	viewerInfo := &models.ViewerInfo{
		IP:        c.ClientIP(),
		UserAgent: c.GetHeader("User-Agent"),
		Referer:   c.GetHeader("Referer"),
	}

	note, err := h.noteService.GetPublicNoteByID(shareLink.NoteID, viewerInfo)
	if err != nil {
		fmt.Printf("GetPublicNoteByID error: %v\n", err)
		utils.NotFound(c, "笔记不存在")
		return
	}

	fmt.Printf("Returning note: %+v\n", note)

	// 异步更新访问计数
	go func() {
		h.db.Model(&shareLink).Update("visit_count", gorm.Expr("visit_count + 1"))
	}()

	utils.Success(c, note)
}

func generateRandomString(length int) (string, error) {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}