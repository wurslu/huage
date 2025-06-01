package handlers

import (
	"fmt"
	"mime/multipart"
	"net/http"
	"notes-backend/internal/config"
	"notes-backend/internal/services"
	"notes-backend/internal/utils"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

type FileHandler struct {
	fileService *services.FileService
	config      *config.Config
}

func NewFileHandler(fileService *services.FileService, cfg *config.Config) *FileHandler {
	return &FileHandler{
		fileService: fileService,
		config:      cfg,
	}
}

func (h *FileHandler) UploadFile(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	err = c.Request.ParseMultipartForm(h.config.File.MaxDocumentSize)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "文件过大或格式错误")
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "未找到上传文件")
		return
	}
	defer file.Close()

	if err := h.validateFile(header); err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	canUpload, err := h.fileService.CheckUserStorage(userID.(uint), header.Size)
	if err != nil {
		utils.InternalError(c)
		return
	}
	if !canUpload {
		utils.Error(c, http.StatusRequestEntityTooLarge, "存储空间不足")
		return
	}

	attachment, err := h.fileService.UploadFile(uint(noteID), userID.(uint), file, header)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "文件上传成功", attachment)
}

func (h *FileHandler) GetAttachments(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	attachments, err := h.fileService.GetAttachments(uint(noteID), userID.(uint))
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, attachments)
}

func (h *FileHandler) DeleteAttachment(c *gin.Context) {
	userID, _ := c.Get("user_id")
	attachmentIDStr := c.Param("id")

	attachmentID, err := strconv.ParseUint(attachmentIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的附件ID")
		return
	}

	err = h.fileService.DeleteAttachment(uint(attachmentID), userID.(uint))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "附件删除成功", nil)
}

func (h *FileHandler) GetUserStorage(c *gin.Context) {
	userID, _ := c.Get("user_id")

	storage, err := h.fileService.GetUserStorageInfo(userID.(uint))
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, storage)
}

func (h *FileHandler) validateFile(header *multipart.FileHeader) error {
	ext := strings.ToLower(filepath.Ext(header.Filename))
	ext = strings.TrimPrefix(ext, ".")

	isImage := h.config.IsImageType(ext)
	if isImage && header.Size > h.config.File.MaxImageSize {
		return fmt.Errorf("图片文件大小不能超过 %d MB", h.config.File.MaxImageSize/(1024*1024))
	}

	isDocument := h.config.IsDocumentType(ext)
	if isDocument && header.Size > h.config.File.MaxDocumentSize {
		return fmt.Errorf("文档文件大小不能超过 %d MB", h.config.File.MaxDocumentSize/(1024*1024))
	}

	if !isImage && !isDocument {
		return fmt.Errorf("不支持的文件类型: %s", ext)
	}

	return nil
}

func (h *FileHandler) ServeFile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		utils.Unauthorized(c, "请先登录")
		return
	}

	attachmentIDStr := c.Param("id")
	attachmentID, err := strconv.ParseUint(attachmentIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的附件ID")
		return
	}

	// 验证文件权限并获取文件信息
	attachment, err := h.fileService.GetAttachmentByID(uint(attachmentID), userID.(uint))
	if err != nil {
		utils.NotFound(c, "文件不存在或无权限访问")
		return
	}

	// 检查文件是否存在
	if _, err := os.Stat(attachment.FilePath); os.IsNotExist(err) {
		utils.NotFound(c, "文件不存在")
		return
	}

	// 设置响应头
	c.Header("Content-Disposition", fmt.Sprintf("inline; filename=\"%s\"", attachment.OriginalFilename))
	if attachment.MimeType != nil {
		c.Header("Content-Type", *attachment.MimeType)
	}

	// 发送文件
	c.File(attachment.FilePath)
}

func (h *FileHandler) DownloadFile(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		utils.Unauthorized(c, "请先登录")
		return
	}

	attachmentIDStr := c.Param("id")
	attachmentID, err := strconv.ParseUint(attachmentIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的附件ID")
		return
	}

	// 验证文件权限并获取文件信息
	attachment, err := h.fileService.GetAttachmentByID(uint(attachmentID), userID.(uint))
	if err != nil {
		utils.NotFound(c, "文件不存在或无权限访问")
		return
	}

	// 检查文件是否存在
	if _, err := os.Stat(attachment.FilePath); os.IsNotExist(err) {
		utils.NotFound(c, "文件不存在")
		return
	}

	// 设置下载响应头
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", attachment.OriginalFilename))
	if attachment.MimeType != nil {
		c.Header("Content-Type", *attachment.MimeType)
	}

	// 发送文件
	c.File(attachment.FilePath)
}