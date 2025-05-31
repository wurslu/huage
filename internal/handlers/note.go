package handlers

import (
	"net/http"
	"notes-backend/internal/models"
	"notes-backend/internal/services"
	"notes-backend/internal/utils"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
)

type NoteHandler struct {
	noteService *services.NoteService
	validator   *validator.Validate
}

func NewNoteHandler(noteService *services.NoteService) *NoteHandler {
	return &NoteHandler{
		noteService: noteService,
		validator:   validator.New(),
	}
}

func (h *NoteHandler) GetNotes(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req models.NoteListRequest
	if err := c.ShouldBindQuery(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	// 设置默认值
	if req.Page <= 0 {
		req.Page = 1
	}
	if req.Limit <= 0 {
		req.Limit = 20
	}
	if req.Limit > 100 {
		req.Limit = 100
	}
	if req.Sort == "" {
		req.Sort = "created_at"
	}
	if req.Order == "" {
		req.Order = "desc"
	}

	notes, pagination, err := h.noteService.GetNotes(userID.(uint), &req)
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, gin.H{
		"notes":      notes,
		"pagination": pagination,
	})
}

func (h *NoteHandler) GetNote(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	note, err := h.noteService.GetNoteByID(uint(noteID), userID.(uint))
	if err != nil {
		utils.NotFound(c, "笔记不存在")
		return
	}

	utils.Success(c, note)
}

func (h *NoteHandler) CreateNote(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req models.NoteCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	// 验证请求参数
	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	// 设置默认内容类型
	if req.ContentType == "" {
		req.ContentType = "markdown"
	}

	note, err := h.noteService.CreateNote(userID.(uint), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "创建成功", note)
}

func (h *NoteHandler) UpdateNote(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	var req models.NoteUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	// 验证请求参数
	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	note, err := h.noteService.UpdateNote(uint(noteID), userID.(uint), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "更新成功", note)
}

func (h *NoteHandler) DeleteNote(c *gin.Context) {
	userID, _ := c.Get("user_id")
	noteIDStr := c.Param("id")

	noteID, err := strconv.ParseUint(noteIDStr, 10, 32)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的笔记ID")
		return
	}

	err = h.noteService.DeleteNote(uint(noteID), userID.(uint))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "删除成功", nil)
}

func (h *NoteHandler) GetUserStats(c *gin.Context) {
	userID, _ := c.Get("user_id")

	stats, err := h.noteService.GetUserStats(userID.(uint))
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, stats)
}