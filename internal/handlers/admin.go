// internal/handlers/admin.go - 添加管理员附件管理功能
package handlers

import (
	"net/http"
	"notes-backend/internal/services"
	"notes-backend/internal/utils"
	"strconv"

	"github.com/gin-gonic/gin"
)

type AdminHandler struct {
	fileService *services.FileService
}

func NewAdminHandler(fileService *services.FileService) *AdminHandler {
	return &AdminHandler{
		fileService: fileService,
	}
}

// 获取软删除的附件列表
func (h *AdminHandler) GetDeletedAttachments(c *gin.Context) {
	// 这里可以添加获取软删除附件的逻辑
	// 暂时返回成功响应
	utils.Success(c, gin.H{"message": "功能待实现"})
}

// 彻底删除附件（包括物理文件）
func (h *AdminHandler) PermanentlyDeleteAttachment(c *gin.Context) {
	attachmentIDStr := c.Param("id")

	attachmentID, err := strconv.ParseUint(attachmentIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的附件ID")
		return
	}

	err = h.fileService.PermanentlyDeleteAttachment(uint(attachmentID))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "附件彻底删除成功", nil)
}

// 恢复软删除的附件
func (h *AdminHandler) RestoreAttachment(c *gin.Context) {
	userID, _ := c.Get("user_id")
	attachmentIDStr := c.Param("id")

	attachmentID, err := strconv.ParseUint(attachmentIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的附件ID")
		return
	}

	err = h.fileService.RestoreAttachment(uint(attachmentID), userID.(uint))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "附件恢复成功", nil)
}

// 重新计算用户存储统计
func (h *AdminHandler) RecalculateUserStorage(c *gin.Context) {
	userIDStr := c.Param("userId")

	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的用户ID")
		return
	}

	err = h.fileService.RecalculateUserStorage(uint(userID))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "存储统计重新计算成功", nil)
}