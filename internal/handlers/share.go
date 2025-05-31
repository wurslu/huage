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
	db        *gorm.DB
	noteService *services.NoteService 
	validator *validator.Validate
}

func NewShareHandler(db *gorm.DB, noteService *services.NoteService) *ShareHandler {
	return &ShareHandler{
		db:          db,
		noteService: noteService, 
		validator:   validator.New(),
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
	c.ShouldBindJSON(&req)

	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ? AND is_public = ?", noteID, userID, true).First(&note).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			utils.Error(c, http.StatusNotFound, "笔记不存在或非公开笔记")
		} else {
			utils.InternalError(c)
		}
		return
	}

	var existingShare models.ShareLink
	if err := h.db.Where("note_id = ? AND is_active = ?", noteID, true).First(&existingShare).Error; err == nil {
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

func (h *ShareHandler) GetShareInfo(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		utils.NotFound(c, "笔记不存在")
		return
	}

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

func (h *ShareHandler) DeleteShareLink(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	var note models.Note
	if err := h.db.Where("id = ? AND user_id = ?", noteID, userID).First(&note).Error; err != nil {
		utils.NotFound(c, "笔记不存在")
		return
	}

	result := h.db.Model(&models.ShareLink{}).Where("note_id = ?", noteID).Update("is_active", false)
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

	if shareLink.ExpireTime != nil && time.Now().After(*shareLink.ExpireTime) {
		utils.Error(c, http.StatusGone, "分享链接已过期")
		return
	}

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

	// 更新分享链接访问次数
	h.db.Model(&shareLink).Update("visit_count", gorm.Expr("visit_count + 1"))

	utils.Success(c, note)
}

func generateRandomString(length int) (string, error) {
	bytes := make([]byte, length/2)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}