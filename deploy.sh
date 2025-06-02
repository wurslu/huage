#!/bin/bash

# =============================================================================
# Notes Backend CentOS 一键部署脚本
# 支持自动配置域名、HTTPS证书、Docker、Nginx等
# =============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_NAME="notes-backend"
PROJECT_DIR="/opt/$PROJECT_NAME"
DOCKER_IMAGE="your-registry/notes-backend:latest"
APP_PORT=9191
DEFAULT_DOMAIN="huage.api.withgo.cn"

# 日志函数
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

log_success() {
    echo -e "${PURPLE}[SUCCESS]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ███╗   ██╗ ██████╗ ████████╗███████╗███████╗
    ████╗  ██║██╔═══██╗╚══██╔══╝██╔════╝██╔════╝
    ██╔██╗ ██║██║   ██║   ██║   █████╗  ███████╗
    ██║╚██╗██║██║   ██║   ██║   ██╔══╝  ╚════██║
    ██║ ╚████║╚██████╔╝   ██║   ███████╗███████║
    ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚══════╝╚══════╝
    
    📝 个人笔记管理系统 - 一键部署脚本
    🔧 自动配置 Docker + Nginx + HTTPS
    🌐 域名: huage.api.withgo.cn
    🚀 让我们开始部署吧！
EOF
    echo -e "${NC}"
    sleep 2
}

# 收集用户输入
collect_user_input() {
    log_step "收集部署配置信息"
    
    # 域名配置
    echo -e "${CYAN}请输入你的域名 (默认: $DEFAULT_DOMAIN):${NC}"
    read -p "> " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
    
    # 邮箱配置（用于 Let's Encrypt）
    echo -e "${CYAN}请输入你的邮箱 (用于 Let's Encrypt 证书):${NC}"
    read -p "> " EMAIL
    while [[ ! "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
        log_error "请输入有效的邮箱地址"
        read -p "> " EMAIL
    done
    
    # Vercel 数据库配置
    echo -e "${CYAN}请输入 Vercel Postgres 数据库连接字符串:${NC}"
    echo -e "${YELLOW}格式: postgresql://user:password@host:5432/database?sslmode=require${NC}"
    read -p "> " VERCEL_POSTGRES_URL
    while [[ -z "$VERCEL_POSTGRES_URL" ]]; do
        log_error "数据库连接字符串不能为空"
        read -p "> " VERCEL_POSTGRES_URL
    done
    
    # JWT Secret
    echo -e "${CYAN}请设置 JWT 密钥 (留空自动生成):${NC}"
    read -p "> " JWT_SECRET
    if [[ -z "$JWT_SECRET" ]]; then
        JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        log_info "自动生成 JWT 密钥: $JWT_SECRET"
    fi
    
    # 确认配置
    echo -e "\n${YELLOW}=== 部署配置确认 ===${NC}"
    echo -e "域名: ${GREEN}$DOMAIN${NC}"
    echo -e "邮箱: ${GREEN}$EMAIL${NC}"
    echo -e "应用端口: ${GREEN}$APP_PORT${NC}"
    echo -e "项目目录: ${GREEN}$PROJECT_DIR${NC}"
    echo -e "\n${CYAN}确认开始部署？ (y/N):${NC}"
    read -p "> " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_warn "部署已取消"
        exit 0
    fi
}

# 检测系统信息
detect_system() {
    log_step "检测系统信息"
    
    # 检查操作系统
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
        log_info "检测到 CentOS $OS_VERSION"
    else
        log_error "仅支持 CentOS 系统"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_warn "网络连接检查失败，请确保服务器可以访问互联网"
    fi
    
    # 检查域名解析
    if ! nslookup $DOMAIN &> /dev/null; then
        log_warn "域名 $DOMAIN 解析失败，请确保 DNS 记录已正确配置"
    fi
}

# 安装系统依赖
install_dependencies() {
    log_step "安装系统依赖"
    
    # 更新系统
    log_info "更新系统包..."
    yum update -y
    
    # 安装基础工具
    log_info "安装基础工具..."
    yum install -y epel-release
    yum install -y wget curl git vim nano unzip firewalld yum-utils device-mapper-persistent-data lvm2
    
    # 安装 Docker
    install_docker
    
    # 安装 Docker Compose
    install_docker_compose
    
    # 安装 Certbot
    install_certbot
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装"
        return
    fi
    
    log_info "安装 Docker..."
    
    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    
    # 添加 Docker 仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装 Docker
    yum install -y docker-ce docker-ce-cli containerd.io
    
    # 启动并启用 Docker
    systemctl start docker
    systemctl enable docker
    
    # 测试 Docker 安装
    if docker --version; then
        log_success "Docker 安装成功"
    else
        log_error "Docker 安装失败"
        exit 1
    fi
}

# 安装 Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose 已安装"
        return
    fi
    
    log_info "安装 Docker Compose..."
    
    # 下载 Docker Compose
    COMPOSE_VERSION="2.21.0"
    curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    # 测试 Docker Compose 安装
    if docker-compose --version; then
        log_success "Docker Compose 安装成功"
    else
        log_error "Docker Compose 安装失败"
        exit 1
    fi
}

# 安装 Certbot
install_certbot() {
    if command -v certbot &> /dev/null; then
        log_info "Certbot 已安装"
        return
    fi
    
    log_info "安装 Certbot..."
    yum install -y certbot python3-certbot-nginx
    
    if certbot --version; then
        log_success "Certbot 安装成功"
    else
        log_error "Certbot 安装失败"
        exit 1
    fi
}

# 配置防火墙
setup_firewall() {
    log_step "配置防火墙"
    
    # 启动防火墙
    systemctl start firewalld
    systemctl enable firewalld
    
    # 开放端口
    firewall-cmd --permanent --add-port=22/tcp      # SSH
    firewall-cmd --permanent --add-port=80/tcp      # HTTP
    firewall-cmd --permanent --add-port=443/tcp     # HTTPS
    firewall-cmd --permanent --add-port=$APP_PORT/tcp  # 应用端口
    
    # 重载防火墙配置
    firewall-cmd --reload
    
    log_success "防火墙配置完成"
}

# 创建项目目录结构
create_project_structure() {
    log_step "创建项目目录结构"
    
    # 停止现有服务
    if [ -d "$PROJECT_DIR" ]; then
        log_info "停止现有服务..."
        cd $PROJECT_DIR && docker-compose down 2>/dev/null || true
    fi
    
    # 创建项目目录
    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR
    
    # 创建子目录
    mkdir -p {uploads,logs,nginx/ssl,scripts,backup}
    
    # 设置权限
    chown -R 1001:1001 uploads logs backup
    chmod -R 755 uploads logs backup
    
    log_success "项目目录结构创建完成"
}

# 创建 Docker Compose 配置
create_docker_compose() {
    log_step "创建 Docker Compose 配置"
    
    cat > $PROJECT_DIR/docker-compose.yml << EOF
version: "3.8"

services:
  app:
    image: $DOCKER_IMAGE
    container_name: notes-backend
    restart: unless-stopped
    ports:
      - "$APP_PORT:$APP_PORT"
    environment:
      # 数据库配置
      - DB_MODE=vercel
      - VERCEL_POSTGRES_URL=\${VERCEL_POSTGRES_URL}
      
      # 应用配置
      - JWT_SECRET=\${JWT_SECRET}
      - SERVER_PORT=$APP_PORT
      - GIN_MODE=release
      - FRONTEND_BASE_URL=https://$DOMAIN
      
      # 文件配置
      - UPLOAD_PATH=/app/uploads
      - MAX_IMAGE_SIZE=10485760
      - MAX_DOCUMENT_SIZE=52428800
      - MAX_USER_STORAGE=524288000
    volumes:
      - ./uploads:/app/uploads
      - ./logs:/app/logs
    networks:
      - notes-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:$APP_PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  nginx:
    image: nginx:alpine
    container_name: notes-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./logs/nginx:/var/log/nginx
      - /etc/letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - app
    networks:
      - notes-network

networks:
  notes-network:
    driver: bridge
EOF
    
    log_success "Docker Compose 配置创建完成"
}

# 创建 Nginx 配置
create_nginx_config() {
    log_step "创建 Nginx 配置"
    
    cat > $PROJECT_DIR/nginx/nginx.conf << EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    # 基础配置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # 安全头
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    
    # HTTP 重定向到 HTTPS
    server {
        listen 80;
        server_name $DOMAIN;
        
        # Let's Encrypt 验证
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        # 其他请求重定向到 HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }
    
    # HTTPS 主配置
    server {
        listen 443 ssl http2;
        server_name $DOMAIN;
        
        # SSL 证书配置
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        # SSL 安全配置
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        
        # HSTS 安全头
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        
        # API 代理
        location / {
            proxy_pass http://app:$APP_PORT;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Forwarded-Port \$server_port;
            proxy_cache_bypass \$http_upgrade;
            
            # 超时配置
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        # 健康检查
        location /health {
            proxy_pass http://app:$APP_PORT/health;
            access_log off;
        }
        
        # 静态文件直接访问
        location /uploads/ {
            proxy_pass http://app:$APP_PORT/uploads/;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF
    
    log_success "Nginx 配置创建完成"
}

# 创建环境变量文件
create_env_file() {
    log_step "创建环境变量文件"
    
    cat > $PROJECT_DIR/.env << EOF
# Notes Backend 环境配置
# 生成时间: $(date)

# 数据库配置
VERCEL_POSTGRES_URL="$VERCEL_POSTGRES_URL"

# 应用配置
JWT_SECRET="$JWT_SECRET"
FRONTEND_BASE_URL="https://$DOMAIN"

# 文件上传配置
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000
EOF
    
    # 设置环境变量文件权限
    chmod 600 $PROJECT_DIR/.env
    
    log_success "环境变量文件创建完成"
}

# 获取 SSL 证书
setup_ssl_certificate() {
    log_step "配置 SSL 证书"
    
    # 创建临时 Nginx 配置用于验证
    cat > /tmp/nginx-temp.conf << EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name $DOMAIN;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # 启动临时 Nginx 容器
    docker run -d --name nginx-temp \
        -p 80:80 \
        -v /tmp/nginx-temp.conf:/etc/nginx/nginx.conf:ro \
        -v /var/www/certbot:/var/www/certbot \
        nginx:alpine
    
    # 等待 Nginx 启动
    sleep 5
    
    # 创建 certbot 目录
    mkdir -p /var/www/certbot
    
    # 获取 SSL 证书
    log_info "获取 Let's Encrypt SSL 证书..."
    certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d $DOMAIN
    
    # 停止临时 Nginx 容器
    docker stop nginx-temp && docker rm nginx-temp
    
    # 验证证书是否获取成功
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        log_success "SSL 证书获取成功"
    else
        log_error "SSL 证书获取失败，将使用自签名证书"
        create_self_signed_certificate
    fi
}

# 创建自签名证书（备用方案）
create_self_signed_certificate() {
    log_warn "创建自签名 SSL 证书..."
    
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
        -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
        -subj "/C=CN/ST=State/L=City/O=Organization/CN=$DOMAIN"
    
    log_warn "自签名证书创建完成，浏览器会显示不安全警告"
}

# 创建管理脚本
create_management_scripts() {
    log_step "创建管理脚本"
    
    # 启动脚本
    cat > $PROJECT_DIR/start.sh << 'EOF'
#!/bin/bash
echo "🚀 启动 Notes Backend..."
cd /opt/notes-backend
docker-compose up -d
echo "✅ 服务已启动"
echo "📱 访问地址: https://DOMAIN_PLACEHOLDER"
echo "🏥 健康检查: https://DOMAIN_PLACEHOLDER/health"
EOF
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" $PROJECT_DIR/start.sh
    
    # 停止脚本
    cat > $PROJECT_DIR/stop.sh << 'EOF'
#!/bin/bash
echo "🛑 停止 Notes Backend..."
cd /opt/notes-backend
docker-compose down
echo "✅ 服务已停止"
EOF
    
    # 重启脚本
    cat > $PROJECT_DIR/restart.sh << 'EOF'
#!/bin/bash
echo "🔄 重启 Notes Backend..."
cd /opt/notes-backend
docker-compose down
docker-compose pull
docker-compose up -d
echo "✅ 服务已重启"
EOF
    
    # 查看日志脚本
    cat > $PROJECT_DIR/logs.sh << 'EOF'
#!/bin/bash
echo "📝 查看 Notes Backend 日志..."
cd /opt/notes-backend
docker-compose logs -f --tail=50
EOF
    
    # 状态检查脚本
    cat > $PROJECT_DIR/status.sh << 'EOF'
#!/bin/bash
echo "📊 Notes Backend 状态检查"
echo "================================"
cd /opt/notes-backend
echo "🐳 Docker 容器状态:"
docker-compose ps
echo ""
echo "💾 磁盘使用情况:"
df -h
echo ""
echo "🔗 服务健康检查:"
curl -s https://DOMAIN_PLACEHOLDER/health | jq . || echo "健康检查失败"
EOF
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" $PROJECT_DIR/status.sh
    
    # 设置执行权限
    chmod +x $PROJECT_DIR/*.sh
    
    log_success "管理脚本创建完成"
}

# 创建系统服务
create_systemd_service() {
    log_step "创建系统服务"
    
    cat > /etc/systemd/system/notes-backend.service << EOF
[Unit]
Description=Notes Backend Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd 并启用服务
    systemctl daemon-reload
    systemctl enable notes-backend
    
    log_success "系统服务创建完成"
}

# 设置证书自动续期
setup_certificate_renewal() {
    log_step "设置证书自动续期"
    
    # 创建续期脚本
    cat > /usr/local/bin/renew-certificates.sh << EOF
#!/bin/bash
certbot renew --quiet --webroot --webroot-path=/var/www/certbot
if [ \$? -eq 0 ]; then
    cd $PROJECT_DIR && docker-compose restart nginx
fi
EOF
    
    chmod +x /usr/local/bin/renew-certificates.sh
    
    # 添加 crontab 任务
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-certificates.sh") | crontab -
    
    log_success "证书自动续期配置完成"
}

# 构建或拉取 Docker 镜像
prepare_docker_image() {
    log_step "准备 Docker 镜像"
    
    # 检查是否有 Dockerfile，如果有则构建，否则拉取
    if [ -f "Dockerfile" ]; then
        log_info "发现 Dockerfile，开始构建镜像..."
        docker build -t notes-backend:latest .
        # 更新 docker-compose.yml 中的镜像名
        sed -i "s|$DOCKER_IMAGE|notes-backend:latest|g" $PROJECT_DIR/docker-compose.yml
    else
        log_info "准备拉取预构建镜像..."
        # 这里你需要替换为实际的镜像地址
        log_warn "请确保镜像 $DOCKER_IMAGE 可用，或提供 Dockerfile"
    fi
}

# 启动服务
start_services() {
    log_step "启动服务"
    
    cd $PROJECT_DIR
    
    # 启动服务
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败，请查看日志"
        docker-compose logs
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_step "验证部署"
    
    # 检查端口监听
    if netstat -tlnp | grep -q ":80\|:443\|:$APP_PORT"; then
        log_info "✅ 端口监听正常"
    else
        log_warn "⚠️ 部分端口可能未正常监听"
    fi
    
    # 检查 HTTPS 证书
    if openssl s_client -connect $DOMAIN:443 -servername $DOMAIN < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        log_info "✅ HTTPS 证书验证成功"
    else
        log_warn "⚠️ HTTPS 证书可能有问题"
    fi
    
    # 检查应用健康状态
    sleep 10
    if curl -f -k https://$DOMAIN/health &>/dev/null; then
        log_info "✅ 应用健康检查通过"
    else
        log_warn "⚠️ 应用健康检查失败"
    fi
}

# 显示部署结果
show_deployment_result() {
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
    🎉 部署完成！
    ===============================================
EOF
    echo -e "${NC}"
    
    echo -e "${CYAN}📱 访问信息:${NC}"
    echo -e "   主页: ${GREEN}https://$DOMAIN${NC}"
    echo -e "   健康检查: ${GREEN}https://$DOMAIN/health${NC}"
    echo -e "   API 文档: ${GREEN}https://$DOMAIN/api${NC}"
    
    echo -e "\n${CYAN}🔧 管理命令:${NC}"
    echo -e "   启动服务: ${YELLOW}cd $PROJECT_DIR && ./start.sh${NC}"
    echo -e "   停止服务: ${YELLOW}cd $PROJECT_DIR && ./stop.sh${NC}"
    echo -e "   重启服务: ${YELLOW}cd $PROJECT_DIR && ./restart.sh${NC}"
    echo -e "   查看日志: ${YELLOW}cd $PROJECT_DIR && ./logs.sh${NC}"
    echo -e "   服务状态: ${YELLOW}cd $PROJECT_DIR && ./status.sh${NC}"
    
    echo -e "\n${CYAN}📁 重要目录:${NC}"
    echo -e "   项目目录: ${GREEN}$PROJECT_DIR${NC}"
    echo -e "   上传目录: ${GREEN}$PROJECT_DIR/uploads${NC}"
    echo -e "   日志目录: ${GREEN}$PROJECT_DIR/logs${NC}"
    echo -e "   配置文件: ${GREEN}$PROJECT_DIR/.env${NC}"
    
    echo -e "\n${CYAN}🔐 安全提醒:${NC}"
    echo -e "   1. 请妥善保管 JWT 密钥和数据库连接字符串"
    echo -e "   2. 定期备份数据和配置文件"
    echo -e "   3. 监控服务器资源使用情况"
    echo -e "   4. 定期更新 Docker 镜像和系统包"
    
    echo -e "\n${CYAN}🆘 故障排除:${NC}"
    echo -e "   查看应用日志: ${YELLOW}docker-compose logs app${NC}"
    echo -e "   查看 Nginx 日志: ${YELLOW}docker-compose logs nginx${NC}"
    echo -e "   重启所有服务: ${YELLOW}systemctl restart notes-backend${NC}"
    echo -e "   检查防火墙: ${YELLOW}firewall-cmd --list-all${NC}"
    
    echo -e "\n${GREEN}🎯 下一步操作:${NC}"
    echo -e "   1. 访问 https://$DOMAIN 测试功能"
    echo -e "   2. 注册第一个用户账号"
    echo -e "   3. 配置前端应用（如果有）"
    echo -e "   4. 设置定期备份策略"
    
    echo -e "\n${PURPLE}===============================================${NC}"
    echo -e "${GREEN}✨ Notes Backend 部署成功！享受你的笔记系统吧！ ✨${NC}"
    echo -e "${PURPLE}===============================================${NC}"
}

# 清理函数
cleanup_on_error() {
    log_error "部署过程中出现错误，正在清理..."
    
    # 停止可能的临时容器
    docker stop nginx-temp 2>/dev/null || true
    docker rm nginx-temp 2>/dev/null || true
    
    # 不删除已创建的文件，便于调试
    log_info "请检查错误日志，修复问题后重新运行脚本"
    exit 1
}

# 主函数
main() {
    # 设置错误处理
    trap cleanup_on_error ERR
    
    # 执行部署步骤
    show_welcome
    check_root
    collect_user_input
    detect_system
    install_dependencies
    setup_firewall
    create_project_structure
    create_docker_compose
    create_nginx_config
    create_env_file
    setup_ssl_certificate
    create_management_scripts
    create_systemd_service
    setup_certificate_renewal
    prepare_docker_image
    start_services
    verify_deployment
    show_deployment_result
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi