# Notes Backend Makefile

# 变量定义
BINARY_NAME=notes-backend
MAIN_PATH=./cmd/server/main.go
BUILD_DIR=./build
DOCKER_IMAGE=notes-backend
DOCKER_TAG=latest

# Go 相关变量
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod
GOFMT=gofmt

# 构建信息
VERSION ?= $(shell git describe --tags --always --dirty)
BUILD_TIME = $(shell date +%Y-%m-%d\ %H:%M:%S)
GIT_COMMIT = $(shell git rev-parse --short HEAD)

# 编译标志
LDFLAGS=-ldflags "-X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME) -X main.GitCommit=$(GIT_COMMIT)"

.PHONY: all build clean test deps help dev prod docker docker-build docker-run docker-stop

# 默认目标
all: clean deps test build

# 显示帮助信息
help:
	@echo "Notes Backend Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help          显示此帮助信息"
	@echo "  deps          安装依赖"
	@echo "  build         构建二进制文件"
	@echo "  clean         清理构建文件"
	@echo "  test          运行测试"
	@echo "  dev           开发模式运行"
	@echo "  prod          生产模式运行"
	@echo "  docker-build  构建 Docker 镜像"
	@echo "  docker-run    运行 Docker 容器"
	@echo "  docker-stop   停止 Docker 容器"
	@echo "  deploy        部署到生产环境"
	@echo "  fmt           格式化代码"
	@echo "  lint          代码检查"

# 安装依赖
deps:
	@echo "📦 Installing dependencies..."
	$(GOMOD) download
	$(GOMOD) tidy

# 构建二进制文件
build:
	@echo "🔨 Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "✅ Build completed: $(BUILD_DIR)/$(BINARY_NAME)"

# 本地构建（当前平台）
build-local:
	@echo "🔨 Building $(BINARY_NAME) for local platform..."
	@mkdir -p $(BUILD_DIR)
	$(GOBUILD) $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) $(MAIN_PATH)

# 跨平台构建
build-all:
	@echo "🔨 Building for all platforms..."
	@mkdir -p $(BUILD_DIR)
	# Linux
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 $(MAIN_PATH)
	# macOS
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 $(MAIN_PATH)
	# Windows
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe $(MAIN_PATH)

# 清理构建文件
clean:
	@echo "🧹 Cleaning..."
	$(GOCLEAN)
	rm -rf $(BUILD_DIR)
	rm -f $(BINARY_NAME)

# 运行测试
test:
	@echo "🧪 Running tests..."
	$(GOTEST) -v ./...

# 运行测试并生成覆盖率报告
test-coverage:
	@echo "🧪 Running tests with coverage..."
	$(GOTEST) -v -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out -o coverage.html
	@echo "📊 Coverage report generated: coverage.html"

# 开发模式运行
dev:
	@echo "🚀 Starting development server..."
	@if [ ! -f .env ]; then echo "⚠️  .env file not found. Please copy .env.example to .env"; exit 1; fi
	GIN_MODE=debug $(GOCMD) run $(MAIN_PATH)

# 生产模式运行
prod: build
	@echo "🚀 Starting production server..."
	@if [ ! -f .env ]; then echo "⚠️  .env file not found. Please copy .env.example to .env"; exit 1; fi
	$(BUILD_DIR)/$(BINARY_NAME)

# 代码格式化
fmt:
	@echo "🎨 Formatting code..."
	$(GOFMT) -w .

# 代码检查
lint:
	@echo "🔍 Running linter..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "⚠️  golangci-lint not installed. Install it with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

# 安装开发工具
install-tools:
	@echo "🛠️  Installing development tools..."
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/cosmtrek/air@latest

# 热重载开发
dev-watch:
	@echo "🔥 Starting development server with hot reload..."
	@if command -v air >/dev/null 2>&1; then \
		air; \
	else \
		echo "⚠️  Air not installed. Installing..."; \
		go install github.com/cosmtrek/air@latest; \
		air; \
	fi

# Docker 构建
docker-build:
	@echo "🐳 Building Docker image..."
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

# Docker 运行
docker-run:
	@echo "🐳 Running Docker container..."
	docker-compose up -d

# Docker 停止
docker-stop:
	@echo "🐳 Stopping Docker containers..."
	docker-compose down

# Docker 日志
docker-logs:
	@echo "📋 Showing Docker logs..."
	docker-compose logs -f notes-backend

# 数据库迁移
migrate-up:
	@echo "📊 Running database migrations..."
	$(GOCMD) run $(MAIN_PATH) -migrate

# 数据库备份
backup:
	@echo "💾 Creating database backup..."
	docker-compose run --rm backup

# 部署到生产环境
deploy: test build docker-build
	@echo "🚀 Deploying to production..."
	@echo "⚠️  Make sure you have configured your production environment!"
	# 这里添加你的部署脚本
	# 例如：scp, rsync, kubectl apply 等

# 创建发布
release: clean test build-all
	@echo "📦 Creating release $(VERSION)..."
	@mkdir -p releases/$(VERSION)
	@cp $(BUILD_DIR)/* releases/$(VERSION)/
	@echo "✅ Release $(VERSION) created in releases/$(VERSION)/"

# 健康检查
health:
	@echo "🏥 Checking application health..."
	@curl -f http://localhost:8080/health || echo "❌ Application is not healthy"

# 初始化项目
init:
	@echo "🎯 Initializing project..."
	@if [ ! -f .env ]; then cp .env.example .env; echo "📝 Created .env file from .env.example"; fi
	@mkdir -p uploads logs backup
	@echo "📁 Created required directories"
	$(MAKE) deps
	@echo "✅ Project initialized successfully!"

# 完整的开发环境设置
setup: init install-tools
	@echo "🎯 Setting up development environment..."
	@echo "✅ Development environment ready!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Configure your .env file"
	@echo "2. Start PostgreSQL database"
	@echo "3. Run: make dev"