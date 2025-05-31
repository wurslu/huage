package handlers

import (
	"net/http"
	"notes-backend/internal/config"
	"notes-backend/internal/models"
	"notes-backend/internal/services"
	"notes-backend/internal/utils"

	"github.com/gin-gonic/gin"
	"github.com/go-playground/validator/v10"
)

type AuthHandler struct {
	authService *services.AuthService
	config      *config.Config
	validator   *validator.Validate
}

func NewAuthHandler(authService *services.AuthService, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		config:      cfg,
		validator:   validator.New(),
	}
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req models.UserRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	// 验证请求参数
	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	// 注册用户
	user, err := h.authService.Register(&req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	// 生成 JWT Token
	token, err := utils.GenerateToken(
		user.ID, user.Username, user.Email, user.Role,
		h.config.JWT.Secret, h.config.JWT.ExpireHours)
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.SuccessWithMessage(c, "注册成功", models.UserResponse{
		User:  user,
		Token: token,
	})
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req models.UserLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "请求参数错误")
		return
	}

	// 验证请求参数
	if err := h.validator.Struct(&req); err != nil {
		utils.ValidationError(c, err.Error())
		return
	}

	// 用户登录
	user, err := h.authService.Login(&req)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, err.Error())
		return
	}

	// 生成 JWT Token
	token, err := utils.GenerateToken(
		user.ID, user.Username, user.Email, user.Role,
		h.config.JWT.Secret, h.config.JWT.ExpireHours)
	if err != nil {
		utils.InternalError(c)
		return
	}

	utils.SuccessWithMessage(c, "登录成功", models.UserResponse{
		User:  user,
		Token: token,
	})
}

func (h *AuthHandler) GetMe(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		utils.Unauthorized(c, "请先登录")
		return
	}

	// 获取用户信息
	user, err := h.authService.GetUserByID(userID.(int))
	if err != nil {
		utils.InternalError(c)
		return
	}

	// 获取存储信息
	storage, err := h.authService.GetUserStorage(userID.(int))
	if err != nil {
		utils.InternalError(c)
		return
	}

	response := gin.H{
		"id":       user.ID,
		"username": user.Username,
		"email":    user.Email,
		"avatar":   user.Avatar,
		"role":     user.Role,
		"storage": gin.H{
			"used_space":     storage.UsedSpace,
			"max_space":      h.config.File.MaxUserStorage,
			"file_count":     storage.FileCount,
			"image_count":    storage.ImageCount,
			"document_count": storage.DocumentCount,
		},
		"created_at": user.CreatedAt,
		"updated_at": user.UpdatedAt,
	}

	utils.Success(c, response)
}

func (h *AuthHandler) Logout(c *gin.Context) {
	// JWT 是无状态的，客户端删除 token 即可
	utils.SuccessWithMessage(c, "退出成功", nil)
}