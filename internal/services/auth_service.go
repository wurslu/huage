// internal/services/auth_service.go
package services

import (
	"database/sql"
	"fmt"
	"notes-backend/internal/models"
	"notes-backend/internal/utils"
)

type AuthService struct {
	db *sql.DB
}

func NewAuthService(db *sql.DB) *AuthService {
	return &AuthService{db: db}
}

func (s *AuthService) Register(req *models.UserRegisterRequest) (*models.User, error) {
	// 检查用户名是否存在
	var exists bool
	err := s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)", req.Username).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, fmt.Errorf("用户名已存在")
	}

	// 检查邮箱是否存在
	err = s.db.QueryRow("SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)", req.Email).Scan(&exists)
	if err != nil {
		return nil, err
	}
	if exists {
		return nil, fmt.Errorf("邮箱已存在")
	}

	// 加密密码
	hashedPassword, err := utils.HashPassword(req.Password)
	if err != nil {
		return nil, err
	}

	// 创建用户
	var user models.User
	err = s.db.QueryRow(`
		INSERT INTO users (username, email, password_hash, role, is_active)
		VALUES ($1, $2, $3, 'user', true)
		RETURNING id, username, email, role, is_active, created_at, updated_at`,
		req.Username, req.Email, hashedPassword).Scan(
		&user.ID, &user.Username, &user.Email, &user.Role, &user.IsActive, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		return nil, err
	}

	// 初始化用户存储记录
	_, err = s.db.Exec(`
		INSERT INTO user_storage (user_id, used_space, file_count, image_count, document_count)
		VALUES ($1, 0, 0, 0, 0)`,
		user.ID)

	if err != nil {
		return nil, err
	}

	return &user, nil
}

func (s *AuthService) Login(req *models.UserLoginRequest) (*models.User, error) {
	var user models.User
	err := s.db.QueryRow(`
		SELECT id, username, email, password_hash, avatar, role, is_active, created_at, updated_at
		FROM users 
		WHERE email = $1 AND is_active = true`,
		req.Email).Scan(
		&user.ID, &user.Username, &user.Email, &user.PasswordHash, 
		&user.Avatar, &user.Role, &user.IsActive, &user.CreatedAt, &user.UpdatedAt)

	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("邮箱或密码错误")
	}
	if err != nil {
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

func (s *AuthService) GetUserByID(userID int) (*models.User, error) {
	var user models.User
	err := s.db.QueryRow(`
		SELECT id, username, email, avatar, role, is_active, created_at, updated_at
		FROM users 
		WHERE id = $1 AND is_active = true`,
		userID).Scan(
		&user.ID, &user.Username, &user.Email, &user.Avatar, 
		&user.Role, &user.IsActive, &user.CreatedAt, &user.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return &user, nil
}

func (s *AuthService) GetUserStorage(userID int) (*models.UserStorage, error) {
	var storage models.UserStorage
	err := s.db.QueryRow(`
		SELECT user_id, used_space, file_count, image_count, document_count, updated_at
		FROM user_storage 
		WHERE user_id = $1`,
		userID).Scan(
		&storage.UserID, &storage.UsedSpace, &storage.FileCount, 
		&storage.ImageCount, &storage.DocumentCount, &storage.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return &storage, nil
}

