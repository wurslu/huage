#!/bin/bash
# 完整的生产环境部署脚本
# 使用方法: ./deploy.sh

set -e

# 配置变量
DOMAIN="huage.api.withgo.cn"
EMAIL="your-email@example.com"  # 请替换为你的邮箱
PROJECT_DIR="/opt/notes-backend"
APP_PORT="9191"
NGINX_HTTP_PORT="80"
NGINX_HTTPS_PORT="443"
DB_PASSWORD="your_secure_db_password_$(date +%s)"
JWT_SECRET="notes-jwt-secret-$(openssl rand -hex 32)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        echo "请使用: sudo ./deploy.sh"
        exit 1
    fi
}

# 检查系统要求
check_system() {
    log_step "检查系统要求..."
    
    # 检查 Ubuntu/Debian
    if ! command -v apt-get &> /dev/null; then
        log_error "此脚本仅支持 Ubuntu/Debian 系统"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "网络连接失败，请检查网络设置"
        exit 1
    fi
    
    log_info "系统检查通过"
}

# 更新系统
update_system() {
    log_step "更新系统包..."
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget git unzip software-properties-common
}

# 安装 Docker
install_docker() {
    log_step "安装 Docker..."
    
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装"
        return
    fi
    
    # 卸载旧版本
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # 安装依赖
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 添加 Docker GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加 Docker 仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # 启动 Docker
    systemctl enable docker
    systemctl start docker
    
    log_info "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    log_step "安装 Docker Compose..."
    
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose 已安装"
        return
    fi
    
    # 下载最新版本
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 设置权限
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_info "Docker Compose 安装完成"
}

# 安装 Nginx
install_nginx() {
    log_step "安装 Nginx..."
    
    if command -v nginx &> /dev/null; then
        log_info "Nginx 已安装"
        return
    fi
    
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    
    log_info "Nginx 安装完成"
}

# 安装 Certbot
install_certbot() {
    log_step "安装 Certbot..."
    
    if command -v certbot &> /dev/null; then
        log_info "Certbot 已安装"
        return
    fi
    
    apt-get install -y certbot python3-certbot-nginx
    
    log_info "Certbot 安装完成"
}

# 配置防火墙
setup_firewall() {
    log_step "配置防火墙..."
    
    # 安装 UFW
    apt-get install -y ufw
    
    # 重置防火墙规则
    ufw --force reset
    
    # 允许必要端口
    ufw allow ssh
    ufw allow $NGINX_HTTP_PORT
    ufw allow $NGINX_HTTPS_PORT
    ufw allow $APP_PORT  # 应用端口（仅内部访问）
    
    # 启用防火墙
    ufw --force enable
    
    log_info "防火墙配置完成"
}

# 创建项目目录
setup_project_directory() {
    log_step "设置项目目录..."
    
    # 创建项目目录
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR
    
    # 创建必要的子目录
    mkdir -p {nginx,ssl,uploads,logs,backup,scripts}
    
    log_info "项目目录创建完成: $PROJECT_DIR"
}

# 创建环境配置文件
create_env_file() {
    log_step "创建环境配置文件..."
    
    cat > $PROJECT_DIR/.env << EOF
# Notes Backend Production Environment
# Generated on $(date)

# Database Configuration
DB_HOST=postgres
DB_PORT=5432
DB_USER=notes_user
DB_PASSWORD=$DB_PASSWORD
DB_NAME=notes_db

# JWT Configuration
JWT_SECRET=$JWT_SECRET

# Server Configuration
SERVER_PORT=$APP_PORT
GIN_MODE=release

# File Upload Configuration
UPLOAD_PATH=./uploads
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000

# Frontend Configuration
FRONTEND_BASE_URL=https://$DOMAIN

# Logging Configuration
LOG_LEVEL=info
LOG_FILE=./logs/app.log

# Production Settings
RATE_LIMIT=100
CORS_ORIGINS=https://$DOMAIN
EOF
    
    log_info "环境配置文件创建完成"
}

# 创建 Docker Compose 配置
create_docker_compose() {
    log_step "创建 Docker Compose 配置..."
    
    cat > $PROJECT_DIR/docker-compose.yml << EOF
version: '3.8'

services:
  notes-backend:
    image: notes-backend:latest
    container_name: notes-backend
    restart: unless-stopped
    ports:
      - "127.0.0.1:$APP_PORT:$APP_PORT"
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=notes_user
      - DB_PASSWORD=$DB_PASSWORD
      - DB_NAME=notes_db
      - JWT_SECRET=$JWT_SECRET
      - GIN_MODE=release
      - SERVER_PORT=$APP_PORT
      - FRONTEND_BASE_URL=https://$DOMAIN
      - LOG_LEVEL=info
    volumes:
      - ./uploads:/app/uploads
      - ./logs:/app/logs
      - ./backup:/app/backup
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - notes-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:$APP_PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  postgres:
    image: postgres:15-alpine
    container_name: notes-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=notes_user
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_DB=notes_db
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backup:/backup
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - notes-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U notes_user -d notes_db"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

volumes:
  postgres_data:
    driver: local

networks:
  notes-network:
    driver: bridge
EOF
    
    log_info "Docker Compose 配置创建完成"
}

# 创建 Nginx 配置
create_nginx_config() {
    log_step "创建 Nginx 配置..."
    
    # 创建主配置文件
    cat > /etc/nginx/sites-available/$DOMAIN << EOF
# Notes Backend Nginx Configuration
# Domain: $DOMAIN
# Generated on $(date)

# Rate limiting
limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=auth:10m rate=5r/s;

# HTTP Server (重定向到 HTTPS)
server {
    listen $NGINX_HTTP_PORT;
    listen [::]:$NGINX_HTTP_PORT;
    server_name $DOMAIN;

    # Let's Encrypt 验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    # 重定向其他请求到 HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS Server
server {
    listen $NGINX_HTTPS_PORT ssl http2;
    listen [::]:$NGINX_HTTPS_PORT ssl http2;
    server_name $DOMAIN;

    # SSL 证书路径（Certbot 会自动配置）
    # ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL 配置
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # 现代 SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (可选，谨慎使用)
    # add_header Strict-Transport-Security "max-age=63072000" always;

    # 安全头
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 客户端最大请求大小
    client_max_body_size 50M;

    # 根路径提示
    location = / {
        return 200 'Notes Backend API Server is running!';
        add_header Content-Type text/plain;
    }

    # API 代理
    location /api/ {
        # 限流
        limit_req zone=api burst=20 nodelay;
        
        # 代理到后端应用
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # 超时设置
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # 认证 API 特殊限流
    location /api/auth/ {
        limit_req zone=auth burst=10 nodelay;
        
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 健康检查
    location /health {
        proxy_pass http://127.0.0.1:$APP_PORT;
        access_log off;
    }

    # 阻止访问敏感文件
    location ~ /\\. {
        deny all;
    }
    
    location ~ \\.(env|config)\$ {
        deny all;
    }

    # 日志配置
    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log /var/log/nginx/$DOMAIN.error.log;
}
EOF

    # 启用站点
    ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    
    # 删除默认站点（如果存在）
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试配置
    nginx -t
    
    log_info "Nginx 配置创建完成"
}

# 获取 SSL 证书
setup_ssl() {
    log_step "设置 SSL 证书..."
    
    # 重启 Nginx 以应用新配置
    systemctl reload nginx
    
    # 获取 SSL 证书
    log_info "正在为域名 $DOMAIN 获取 SSL 证书..."
    
    if certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect; then
        log_info "SSL 证书获取成功"
    else
        log_warn "SSL 证书获取失败，请检查域名解析和网络连接"
        log_warn "你可以稍后手动运行: certbot --nginx -d $DOMAIN"
    fi
    
    # 设置自动续期
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    log_info "SSL 自动续期已设置"
}

# 创建 Dockerfile
create_dockerfile() {
    log_step "创建 Dockerfile..."
    
    cat > $PROJECT_DIR/Dockerfile << 'EOF'
# 多阶段构建 Dockerfile
FROM golang:1.23-alpine AS builder

# 安装必要的包
RUN apk add --no-cache git ca-certificates tzdata

# 设置工作目录
WORKDIR /app

# 复制 go mod 文件
COPY go.mod go.sum ./

# 下载依赖
RUN go mod download

# 复制源码
COPY . .

# 构建应用
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-w -s -extldflags "-static"' \
    -a -installsuffix cgo \
    -o main cmd/server/main.go

# 运行阶段
FROM alpine:latest

# 安装必要的包
RUN apk --no-cache add ca-certificates tzdata wget

# 设置时区
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 创建非 root 用户
RUN adduser -D -s /bin/sh notes

# 设置工作目录
WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /app/main ./

# 创建必要的目录并设置权限
RUN mkdir -p uploads logs backup && \
    chown -R notes:notes /app

# 暴露端口
EXPOSE 9191

# 切换到非 root 用户
USER notes

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9191/health || exit 1

# 运行应用
CMD ["./main"]
EOF
    
    log_info "Dockerfile 创建完成"
}

# 创建管理脚本
create_management_scripts() {
    log_step "创建管理脚本..."
    
    # 备份脚本
    cat > $PROJECT_DIR/scripts/backup.sh << 'EOF'
#!/bin/bash
# 数据库和文件备份脚本

BACKUP_DIR="/opt/notes-backend/backup"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

echo "开始备份..."

# 备份数据库
docker-compose exec -T postgres pg_dump -U notes_user -d notes_db > $BACKUP_DIR/db_backup_$DATE.sql
gzip $BACKUP_DIR/db_backup_$DATE.sql

# 备份上传文件
tar -czf $BACKUP_DIR/uploads_backup_$DATE.tar.gz uploads/

# 清理旧备份（保留30天）
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "备份完成: $BACKUP_DIR/db_backup_$DATE.sql.gz"
echo "文件备份: $BACKUP_DIR/uploads_backup_$DATE.tar.gz"
EOF

    # 监控脚本
    cat > $PROJECT_DIR/scripts/monitor.sh << 'EOF'
#!/bin/bash
# 服务监控脚本

echo "=== Notes Backend 服务状态 ==="
echo "时间: $(date)"
echo

# 检查容器状态
echo "Docker 容器状态:"
docker-compose ps

echo

# 检查服务健康
echo "服务健康检查:"
if curl -f http://localhost:9191/health >/dev/null 2>&1; then
    echo "✅ 后端 API 服务正常"
else
    echo "❌ 后端 API 服务异常"
fi

if docker-compose exec postgres pg_isready -U notes_user >/dev/null 2>&1; then
    echo "✅ 数据库服务正常"
else
    echo "❌ 数据库服务异常"
fi

# 检查磁盘空间
echo
echo "磁盘使用情况:"
df -h / | tail -1

# 检查内存使用
echo
echo "内存使用情况:"
free -h

echo
echo "================================"
EOF

    # 更新脚本
    cat > $PROJECT_DIR/scripts/update.sh << 'EOF'
#!/bin/bash
# 应用更新脚本

set -e

echo "开始更新 Notes Backend..."

# 进入项目目录
cd /opt/notes-backend

# 备份当前数据
echo "创建备份..."
./scripts/backup.sh

# 拉取最新代码（如果使用 Git）
# git pull origin main

# 重新构建镜像
echo "重新构建 Docker 镜像..."
docker-compose build --no-cache

# 重启服务
echo "重启服务..."
docker-compose down
docker-compose up -d

# 等待服务启动
echo "等待服务启动..."
sleep 30

# 健康检查
if curl -f http://localhost:9191/health >/dev/null 2>&1; then
    echo "✅ 更新成功！"
else
    echo "❌ 更新失败，请检查日志"
    exit 1
fi

# 清理无用镜像
docker system prune -f

echo "更新完成！"
EOF

    # 设置脚本权限
    chmod +x $PROJECT_DIR/scripts/*.sh
    
    log_info "管理脚本创建完成"
}

# 部署应用
deploy_application() {
    log_step "部署应用..."
    
    cd $PROJECT_DIR
    
    # 检查是否有源码目录
    if [ ! -f "go.mod" ]; then
        log_warn "未找到 Go 项目源码"
        log_info "请将你的项目源码复制到 $PROJECT_DIR"
        log_info "确保包含以下文件："
        log_info "  - go.mod, go.sum"
        log_info "  - cmd/server/main.go"
        log_info "  - internal/ 目录"
        return
    fi
    
    # 构建并启动服务
    log_info "构建 Docker 镜像..."
    docker-compose build
    
    log_info "启动服务..."
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 健康检查
    if curl -f http://localhost:$APP_PORT/health >/dev/null 2>&1; then
        log_info "✅ 应用部署成功！"
    else
        log_warn "⚠️ 应用可能未正常启动，请检查日志"
        docker-compose logs
    fi
}

# 输出部署信息
show_deployment_info() {
    log_step "部署信息"
    
    echo
    echo "🎉 Notes Backend 部署完成！"
    echo
    echo "服务信息:"
    echo "  域名: https://$DOMAIN"
    echo "  API 地址: https://$DOMAIN/api"
    echo "  健康检查: https://$DOMAIN/health"
    echo
    echo "管理命令:"
    echo "  查看状态: cd $PROJECT_DIR && docker-compose ps"
    echo "  查看日志: cd $PROJECT_DIR && docker-compose logs -f"
    echo "  重启服务: cd $PROJECT_DIR && docker-compose restart"
    echo "  停止服务: cd $PROJECT_DIR && docker-compose down"
    echo
    echo "管理脚本:"
    echo "  监控检查: $PROJECT_DIR/scripts/monitor.sh"
    echo "  数据备份: $PROJECT_DIR/scripts/backup.sh"
    echo "  应用更新: $PROJECT_DIR/scripts/update.sh"
    echo
    echo "配置文件:"
    echo "  环境变量: $PROJECT_DIR/.env"
    echo "  Docker Compose: $PROJECT_DIR/docker-compose.yml"
    echo "  Nginx 配置: /etc/nginx/sites-available/$DOMAIN"
    echo
    echo "⚠️ 重要提醒:"
    echo "1. 请确保域名 $DOMAIN 已正确解析到此服务器"
    echo "2. 数据库密码已保存在 $PROJECT_DIR/.env 文件中"
    echo "3. 建议定期运行备份脚本"
    echo "4. SSL 证书会自动续期"
    echo
}

# 主函数
main() {
    echo "🚀 Notes Backend 生产环境部署脚本"
    echo "=================================="
    echo "域名: $DOMAIN"
    echo "端口: $APP_PORT (HTTPS)"
    echo "项目目录: $PROJECT_DIR"
    echo "=================================="
    echo
    
    read -p "确认开始部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "部署已取消"
        exit 0
    fi
    
    # 请求用户输入邮箱
    read -p "请输入你的邮箱地址（用于 SSL 证书）: " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "邮箱地址不能为空"
        exit 1
    fi
    
    # 执行部署步骤
    check_root
    check_system
    update_system
    install_docker
    install_docker_compose
    install_nginx
    install_certbot
    setup_firewall
    setup_project_directory
    create_env_file
    create_docker_compose
    create_dockerfile
    create_nginx_config
    setup_ssl
    create_management_scripts
    deploy_application
    show_deployment_info
    
    log_info "🎉 部署完成！"
}

# 执行主函数
main "$@"