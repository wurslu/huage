package utils

import (
	"net/http"
	"notes-backend/internal/models"

	"github.com/gin-gonic/gin"
)

func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, models.Response{
		Code:    http.StatusOK,
		Message: "成功",
		Data:    data,
	})
}

func SuccessWithMessage(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusOK, models.Response{
		Code:    http.StatusOK,
		Message: message,
		Data:    data,
	})
}

func Error(c *gin.Context, code int, message string) {
	c.JSON(code, models.Response{
		Code:    code,
		Message: message,
	})
}

func ErrorWithData(c *gin.Context, code int, message string, errors interface{}) {
	c.JSON(code, models.Response{
		Code:    code,
		Message: message,
		Errors:  errors,
	})
}

func ValidationError(c *gin.Context, errors interface{}) {
	c.JSON(http.StatusUnprocessableEntity, models.Response{
		Code:    http.StatusUnprocessableEntity,
		Message: "验证失败",
		Errors:  errors,
	})
}

func InternalError(c *gin.Context) {
	c.JSON(http.StatusInternalServerError, models.Response{
		Code:    http.StatusInternalServerError,
		Message: "服务器内部错误",
	})
}

func NotFound(c *gin.Context, message string) {
	if message == "" {
		message = "资源不存在"
	}
	c.JSON(http.StatusNotFound, models.Response{
		Code:    http.StatusNotFound,
		Message: message,
	})
}

func Unauthorized(c *gin.Context, message string) {
	if message == "" {
		message = "未授权访问"
	}
	c.JSON(http.StatusUnauthorized, models.Response{
		Code:    http.StatusUnauthorized,
		Message: message,
	})
}

func Forbidden(c *gin.Context, message string) {
	if message == "" {
		message = "无权限访问"
	}
	c.JSON(http.StatusForbidden, models.Response{
		Code:    http.StatusForbidden,
		Message: message,
	})
}