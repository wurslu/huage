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

type CategoryHandler struct {
	categoryService *services.CategoryService
	validator       *validator.Validate
}

func NewCategoryHandler(categoryService *services.CategoryService) *CategoryHandler {
	return &CategoryHandler{
		categoryService: categoryService,
		validator:       validator.New(),
	}
}

func (h *CategoryHandler) GetCategories(c *gin.Context) {
	userID, _ := c.Get("user_id")

	categories, err := h.categoryService.GetCategoriesTree(userID.(int))
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, categories)
}

func (h *CategoryHandler) CreateCategory(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req models.CategoryCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	category, err := h.categoryService.CreateCategory(userID.(int), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "创建成功", category)
}

func (h *CategoryHandler) UpdateCategory(c *gin.Context) {
	userID, _ := c.Get("user_id")
	categoryIDStr := c.Param("id")

	categoryID, err := strconv.Atoi(categoryIDStr)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的分类ID")
		return
	}

	var req models.CategoryCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	category, err := h.categoryService.UpdateCategory(categoryID, userID.(int), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "更新成功", category)
}

func (h *CategoryHandler) DeleteCategory(c *gin.Context) {
	userID, _ := c.Get("user_id")
	categoryIDStr := c.Param("id")

	categoryID, err := strconv.Atoi(categoryIDStr)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的分类ID")
		return
	}

	err = h.categoryService.DeleteCategory(categoryID, userID.(int))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "删除成功", nil)
}

// internal/handlers/tag.go
type TagHandler struct {
	tagService *services.TagService
	validator  *validator.Validate
}

func NewTagHandler(tagService *services.TagService) *TagHandler {
	return &TagHandler{
		tagService: tagService,
		validator:  validator.New(),
	}
}

func (h *TagHandler) GetTags(c *gin.Context) {
	userID, _ := c.Get("user_id")

	tags, err := h.tagService.GetTags(userID.(int))
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.Success(c, tags)
}

func (h *TagHandler) CreateTag(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req models.TagCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	tag, err := h.tagService.CreateTag(userID.(int), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "创建成功", tag)
}

func (h *TagHandler) UpdateTag(c *gin.Context) {
	userID, _ := c.Get("user_id")
	tagIDStr := c.Param("id")

	tagID, err := strconv.Atoi(tagIDStr)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的标签ID")
		return
	}

	var req models.TagCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	tag, err := h.tagService.UpdateTag(tagID, userID.(int), &req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "更新成功", tag)
}

func (h *TagHandler) DeleteTag(c *gin.Context) {
	userID, _ := c.Get("user_id")
	tagIDStr := c.Param("id")

	tagID, err := strconv.Atoi(tagIDStr)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "无效的标签ID")
		return
	}

	err = h.tagService.DeleteTag(tagID, userID.(int))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.SuccessWithMessage(c, "删除成功", nil)
}