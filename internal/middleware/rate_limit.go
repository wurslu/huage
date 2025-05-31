package middleware

import (
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