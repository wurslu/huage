// internal/middleware/auth.go
package middleware

import (
	"notes-backend/internal/config"
	"notes-backend/internal/models"
	"notes-backend/internal/utils"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func AuthMiddleware(db *gorm.DB, cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := extractToken(c)
		if token == "" {
			utils.Unauthorized(c, "缺少访问令牌")
			c.Abort()
			return
		}

		claims, err := utils.ParseToken(token, cfg.JWT.Secret)
		if err != nil {
			utils.Unauthorized(c, "无效的访问令牌")
			c.Abort()
			return
		}

		// 验证用户是否存在且活跃
		var user models.User
		if err := db.Where("id = ? AND is_active = ?", claims.UserID, true).First(&user).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				utils.Unauthorized(c, "用户不存在或已被禁用")
			} else {
				utils.InternalError(c)
			}
			c.Abort()
			return
		}

		// 将用户信息存储到上下文中
		c.Set("user", &user)
		c.Set("user_id", user.ID)
		c.Next()
	}
}

func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		user, exists := c.Get("user")
		if !exists {
			utils.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}

		u := user.(*models.User)
		if u.Role != "admin" {
			utils.Forbidden(c, "需要管理员权限")
			c.Abort()
			return
		}

		c.Next()
	}
}

func extractToken(c *gin.Context) string {
	// 从 Authorization header 获取
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			return parts[1]
		}
	}

	// 从查询参数获取（用于分享链接等场景）
	token := c.Query("token")
	if token != "" {
		return token
	}

	return ""
}
