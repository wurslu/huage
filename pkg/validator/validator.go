// pkg/validator/validator.go
package validator

import (
	"reflect"
	"strings"

	"github.com/go-playground/validator/v10"
)

var validate *validator.Validate

func init() {
	validate = validator.New()
	
	// 使用 JSON 标签名作为字段名
	validate.RegisterTagNameFunc(func(fld reflect.StructField) string {
		name := strings.SplitN(fld.Tag.Get("json"), ",", 2)[0]
		if name == "-" {
			return ""
		}
		return name
	})

	// 注册自定义验证规则
	registerCustomValidators()
}

func registerCustomValidators() {
	// 验证颜色代码
	validate.RegisterValidation("hexcolor", func(fl validator.FieldLevel) bool {
		color := fl.Field().String()
		if len(color) != 7 {
			return false
		}
		if color[0] != '#' {
			return false
		}
		for _, char := range color[1:] {
			if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')) {
				return false
			}
		}
		return true
	})
}

func ValidateStruct(s interface{}) error {
	return validate.Struct(s)
}

func GetValidator() *validator.Validate {
	return validate
}