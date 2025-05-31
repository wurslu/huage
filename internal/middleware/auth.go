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

// internal/middleware/cors.go
import (
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func CORSMiddleware() gin.HandlerFunc {
	return cors.New(cors.Config{
		AllowOrigins:     []string{"http://localhost:3000", "http://127.0.0.1:3000"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Content-Length", "Accept-Encoding", "X-CSRF-Token", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	})
}

// internal/middleware/logger.go
import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

func LoggerMiddleware() gin.HandlerFunc {
	return gin.LoggerWithFormatter(func(param gin.LogFormatterParams) string {
		logrus.WithFields(logrus.Fields{
			"status_code":  param.StatusCode,
			"latency":      param.Latency,
			"client_ip":    param.ClientIP,
			"method":       param.Method,
			"path":         param.Path,
			"error":        param.ErrorMessage,
		}).Info("HTTP Request")
		return ""
	})
}

// internal/middleware/rate_limit.go
import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type rateLimiter struct {
	visitors map[string]*visitor
	mutex    sync.RWMutex
}

type visitor struct {
	limiter  *tokenBucket
	lastSeen time.Time
}

type tokenBucket struct {
	tokens    int
	capacity  int
	refillRate int
	lastRefill time.Time
	mutex     sync.Mutex
}

var limiter = &rateLimiter{
	visitors: make(map[string]*visitor),
}

func RateLimitMiddleware(requestsPerMinute int) gin.HandlerFunc {
	// 每10分钟清理一次过期的访问者
	go limiter.cleanupRoutine()

	return func(c *gin.Context) {
		ip := c.ClientIP()
		
		if !limiter.allow(ip, requestsPerMinute) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"code":    http.StatusTooManyRequests,
				"message": "请求频率过高，请稍后再试",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

func (rl *rateLimiter) allow(ip string, requestsPerMinute int) bool {
	rl.mutex.Lock()
	defer rl.mutex.Unlock()

	v, exists := rl.visitors[ip]
	if !exists {
		v = &visitor{
			limiter: &tokenBucket{
				tokens:     requestsPerMinute,
				capacity:   requestsPerMinute,
				refillRate: requestsPerMinute,
				lastRefill: time.Now(),
			},
			lastSeen: time.Now(),
		}
		rl.visitors[ip] = v
	}

	v.lastSeen = time.Now()
	return v.limiter.allow()
}

func (tb *tokenBucket) allow() bool {
	tb.mutex.Lock()
	defer tb.mutex.Unlock()

	now := time.Now()
	elapsed := now.Sub(tb.lastRefill)
	tokensToAdd := int(elapsed.Minutes()) * tb.refillRate

	if tokensToAdd > 0 {
		tb.tokens += tokensToAdd
		if tb.tokens > tb.capacity {
			tb.tokens = tb.capacity
		}
		tb.lastRefill = now
	}

	if tb.tokens > 0 {
		tb.tokens--
		return true
	}

	return false
}

func (rl *rateLimiter) cleanupRoutine() {
	for {
		time.Sleep(10 * time.Minute)
		
		rl.mutex.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastSeen) > 10*time.Minute {
				delete(rl.visitors, ip)
			}
		}
		rl.mutex.Unlock()
	}
}