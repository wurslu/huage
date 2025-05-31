package services

import (
	"fmt"
	"notes-backend/internal/models"
	"notes-backend/internal/utils"

	"gorm.io/gorm"
)

type AuthService struct {
	db *gorm.DB
}

func NewAuthService(db *gorm.DB) *AuthService {
	return &AuthService{db: db}
}

func (s *AuthService) Register(req *models.UserRegisterRequest) (*models.User, error) {
	// 检查用户名是否存在
	var count int64
	if err := s.db.Model(&models.User{}).Where("username = ?", req.Username).Count(&count).Error; err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, fmt.Errorf("用户名已存在")
	}

	// 检查邮箱是否存在
	if err := s.db.Model(&models.User{}).Where("email = ?", req.Email).Count(&count).Error; err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, fmt.Errorf("邮箱已存在")
	}

	// 加密密码
	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}

	// 创建用户
	user := models.User{
		Username:     req.Username,
		Email:        req.Email,
		PasswordHash: hashedPassword,
		Role:         "user",
		IsActive:     true,
	}

	if err := s.db.Create(&user).Error; err != nil {
		return nil, err
	}

	// 初始化用户存储记录
	userStorage := models.UserStorage{
		UserID:        user.ID,
		UsedSpace:     0,
		FileCount:     0,
		ImageCount:    0,
		DocumentCount: 0,
	}

	if err := s.db.Create(&userStorage).Error; err != nil {
		return nil, err
	}

	return &user, nil
}

func (s *AuthService) Login(req *models.UserLoginRequest) (*models.User, error) {
	var user models.User
	err := s.db.Where("email = ? AND is_active = ?", req.Email, true).First(&user).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("邮箱或密码错误")
		}
		return nil, err
	}

	// 验证密码
	valid, err := utils.VerifyPassword(req.Password, user.PasswordHash)
	if err != nil {
		return nil, err
	}
	if !valid {
		return nil, fmt.Errorf("邮箱或密码错误")
	}

	return &user, nil
}

func (s *AuthService) GetUserByID(userID uint) (*models.User, error) {
	var user models.User
	err := s.db.Where("id = ? AND is_active = ?", userID, true).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

func (s *AuthService) GetUserStorage(userID uint) (*models.UserStorage, error) {
	var storage models.UserStorage
	err := s.db.Where("user_id = ?", userID).First(&storage).Error
	if err != nil {
		return nil, err
	}
	return &storage, nil
}
