#!/bin/bash


set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${PURPLE}[SUCCESS]${NC} $1"; }

PROJECT_NAME="notes-backend"
PROJECT_DIR="/opt/$PROJECT_NAME"
APP_PORT=9191
DEFAULT_DOMAIN="huage.api.withgo.cn"
DEFAULT_EMAIL="23200804@qq.com"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

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
    
    📝 个人笔记管理系统 - 终极一键部署 (优化版)
    🚀 本地编译 + 完整 HTTPS + 自动证书
    🔧 解决端口冲突、Docker网络、SSL证书问题
    🌐 域名: huage.api.withgo.cn
    ✨ 让我们开始魔法般的部署吧！
EOF
    echo -e "${NC}"
    sleep 3
}

collect_user_input() {
    log_step "收集部署配置信息"
    
    echo -e "${CYAN}请输入你的域名 (默认: $DEFAULT_DOMAIN):${NC}"
    read -p "> " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
    
    echo -e "${CYAN}请输入你的邮箱 (默认: $DEFAULT_EMAIL):${NC}"
    read -p "> " EMAIL
    EMAIL=${EMAIL:-$DEFAULT_EMAIL}
    
    echo -e "${CYAN}请输入 Vercel Postgres 数据库连接字符串:${NC}"
    echo -e "${YELLOW}格式: postgresql://user:password@host:5432/database?sslmode=require${NC}"
    read -p "> " VERCEL_POSTGRES_URL
    while [[ -z "$VERCEL_POSTGRES_URL" ]]; do
        log_error "数据库连接字符串不能为空"
        read -p "> " VERCEL_POSTGRES_URL
    done
    
    echo -e "${CYAN}请设置 JWT 密钥 (留空自动生成):${NC}"
    read -p "> " JWT_SECRET
    if [[ -z "$JWT_SECRET" ]]; then
        JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        log_info "自动生成 JWT 密钥: $JWT_SECRET"
    fi
    
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

detect_system() {
    log_step "检测系统信息"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_NAME="$NAME"
        log_info "检测到系统: $OS_NAME"
        
        case "$OS_ID" in
            "centos"|"rhel"|"rocky"|"almalinux"|"opencloudos")
                PACKAGE_MANAGER="yum"
                log_info "使用 RHEL 系列部署流程"
                ;;
            "ubuntu"|"debian")
                PACKAGE_MANAGER="apt"
                log_info "使用 Debian 系列部署流程"
                ;;
            *)
                if command -v yum &> /dev/null; then
                    PACKAGE_MANAGER="yum"
                    log_info "检测到 yum，使用 RHEL 兼容模式"
                else
                    log_error "不支持的系统"
                    exit 1
                fi
                ;;
        esac
    fi
    
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_info "网络连接正常"
    else
        log_warn "网络连接检查失败"
    fi
}

install_dependencies() {
    log_step "安装系统依赖"
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER update -y
        
        $PACKAGE_MANAGER install -y wget curl git vim nano unzip firewalld device-mapper-persistent-data lvm2 || {
            log_warn "部分包安装失败，继续..."
        }
        
        $PACKAGE_MANAGER install -y dnf-utils || $PACKAGE_MANAGER install -y yum-utils || {
            log_warn "yum-utils 安装失败，继续..."
        }
        
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        apt update
        apt install -y wget curl git vim nano unzip ufw apt-transport-https ca-certificates gnupg lsb-release
    fi
    
    install_go
    install_docker
    install_docker_compose
    install_certbot
}

install_go() {
    if command -v go &> /dev/null; then
        GO_VERSION=$(go version | cut -d' ' -f3)
        log_info "Go 已安装: $GO_VERSION"
        return
    fi
    
    log_info "安装 Go 1.23..."
    
    cd /tmp
    wget -q https://go.dev/dl/go1.23.0.linux-amd64.tar.gz || {
        log_error "Go 下载失败"
        exit 1
    }
    
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
    
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    
    export PATH=$PATH:/usr/local/go/bin
    
    if go version; then
        log_success "Go 安装成功: $(go version)"
    else
        log_error "Go 安装失败"
        exit 1
    fi
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
        return
    fi
    
    log_info "安装 Docker..."
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
            cat > /etc/yum.repos.d/docker-ce.repo << 'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/8/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF
        fi
        
        $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io || {
            log_warn "从官方仓库安装失败，尝试系统仓库..."
            $PACKAGE_MANAGER install -y docker
        }
        
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io
    fi
    
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker 安装成功: $(docker --version)"
}

install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log_info "Docker Compose 已安装: $(docker-compose --version)"
        return
    fi
    
    log_info "安装 Docker Compose..."
    
    curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_success "Docker Compose 安装成功: $(docker-compose --version)"
}

install_certbot() {
    if command -v certbot &> /dev/null; then
        log_info "Certbot 已安装: $(certbot --version)"
        return
    fi
    
    log_info "安装 Certbot..."
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER install -y python3 python3-pip
        pip3 install certbot
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        apt install -y certbot python3-certbot-nginx
    fi
    
    log_success "Certbot 安装成功: $(certbot --version)"
}

setup_firewall() {
    log_step "配置防火墙"
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        systemctl start firewalld || true
        systemctl enable firewalld || true
        firewall-cmd --permanent --add-port=22/tcp || true
        firewall-cmd --permanent --add-port=80/tcp || true
        firewall-cmd --permanent --add-port=443/tcp || true
        firewall-cmd --permanent --add-port=$APP_PORT/tcp || true
        firewall-cmd --reload || true
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        ufw --force enable
        ufw allow 22/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow $APP_PORT/tcp
    fi
    
    log_success "防火墙配置完成"
    log_info "请确保腾讯云安全组已放行以下端口："
    log_info "- 22 (SSH)"
    log_info "- 80 (HTTP)"
    log_info "- 443 (HTTPS)"
    log_info "- $APP_PORT (应用端口)"
}

create_project_structure() {
    log_step "创建项目目录结构"
    
    if [ "$PWD" != "$PROJECT_DIR" ]; then
        if [ -d "$PROJECT_DIR" ]; then
            log_info "备份现有项目目录..."
            mv $PROJECT_DIR $PROJECT_DIR.backup.$(date +%Y%m%d_%H%M%S)
        fi
        
        log_info "复制项目文件到 $PROJECT_DIR..."
        mkdir -p $PROJECT_DIR
        cp -r * $PROJECT_DIR/ 2>/dev/null || {
            log_warn "部分文件复制失败，继续..."
        }
    fi
    
    cd $PROJECT_DIR
    
    mkdir -p {uploads,logs,nginx/ssl,backup,systemd}
    chmod -R 755 uploads logs backup
    
    log_success "项目目录结构创建完成"
}

compile_application() {
    log_step "编译应用"
    
    cd $PROJECT_DIR
    
    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on
    
    log_info "下载 Go 依赖..."
    go mod download
    go mod tidy
    
    log_info "编译应用..."
    go build -ldflags="-w -s" -o notes-backend cmd/server/main.go
    
    if [ -f "notes-backend" ]; then
        chmod +x notes-backend
        log_success "应用编译成功"
    else
        log_error "应用编译失败"
        exit 1
    fi
}

create_configuration() {
    log_step "创建配置文件"
    
    cd $PROJECT_DIR
    
    cat > .env << EOF
DB_MODE=vercel
VERCEL_POSTGRES_URL="$VERCEL_POSTGRES_URL"

JWT_SECRET="$JWT_SECRET"
SERVER_PORT=$APP_PORT
GIN_MODE=release
FRONTEND_BASE_URL=https://$DOMAIN

UPLOAD_PATH=/opt/notes-backend/uploads
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000
EOF
    
    chmod 600 .env
    
    mkdir -p nginx
    cat > nginx/nginx-http.conf << EOF
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    server {
        listen 80;
        server_name $DOMAIN;
        
        location / {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
        
        location /health {
            proxy_pass http://172.17.0.1:$APP_PORT/health;
            access_log off;
        }
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
    }
}
EOF

    cat > nginx/nginx.conf << EOF
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
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    server {
        listen 80;
        server_name $DOMAIN;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }
    
    server {
        listen 443 ssl;
        http2 on;
        server_name $DOMAIN;
        
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        
        location / {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_cache_bypass \$http_upgrade;
            
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location /health {
            proxy_pass http://172.17.0.1:$APP_PORT/health;
            access_log off;
        }
    }
}
EOF
    
    log_success "配置文件创建完成"
}

setup_ssl_certificate() {
    log_step "配置 SSL 证书"
    
    mkdir -p /var/www/certbot
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    log_info "创建临时自签名证书..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
        -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
        -subj "/C=CN/ST=State/L=City/O=Organization/CN=$DOMAIN"
    
    chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    chmod 600 /etc/letsencrypt/live/$DOMAIN/privkey.pem
    
    log_success "临时证书创建完成"
}

create_system_services() {
    log_step "创建系统服务"
    
    cat > /etc/systemd/system/notes-backend.service << EOF
[Unit]
Description=Notes Backend Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/notes-backend
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/notes-nginx-http.service << EOF
[Unit]
Description=Notes Backend Nginx Proxy (HTTP Only)
After=docker.service notes-backend.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$PROJECT_DIR
ExecStartPre=-/usr/bin/docker stop notes-nginx
ExecStartPre=-/usr/bin/docker rm notes-nginx
ExecStart=/usr/bin/docker run -d --name notes-nginx \\
    -p 80:80 \\
    -v $PROJECT_DIR/nginx/nginx-http.conf:/etc/nginx/nginx.conf:ro \\
    -v $PROJECT_DIR/logs:/var/log/nginx \\
    -v /var/www/certbot:/var/www/certbot \\
    --restart unless-stopped \\
    nginx:alpine
ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/notes-nginx.service << EOF
[Unit]
Description=Notes Backend Nginx Proxy (HTTPS)
After=docker.service notes-backend.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$PROJECT_DIR
ExecStartPre=-/usr/bin/docker stop notes-nginx
ExecStartPre=-/usr/bin/docker rm notes-nginx
ExecStart=/usr/bin/docker run -d --name notes-nginx \\
    -p 80:80 -p 443:443 \\
    -v $PROJECT_DIR/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \\
    -v /etc/letsencrypt:/etc/letsencrypt:ro \\
    -v $PROJECT_DIR/logs:/var/log/nginx \\
    -v /var/www/certbot:/var/www/certbot \\
    --restart unless-stopped \\
    nginx:alpine
ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable notes-backend
    
    log_success "系统服务创建完成"
}

handle_nginx_conflicts() {
    log_step "检查并解决 Nginx 端口冲突"
    
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    systemctl mask nginx 2>/dev/null || true
    
    NGINX_PIDS=$(ps aux | grep nginx | grep -v grep | awk '{print $2}' || true)
    if [ -n "$NGINX_PIDS" ]; then
        log_info "发现 nginx 进程，正在清理..."
        for pid in $NGINX_PIDS; do
            kill -9 $pid 2>/dev/null || true
        done
        log_success "已清理冲突的 nginx 进程"
    fi
    
    log_info "重启 Docker 服务以解决网络问题..."
    systemctl restart docker
    sleep 5
    
    if netstat -tlnp | grep -q ":80 "; then
        log_error "端口 80 仍被占用："
        netstat -tlnp | grep ":80 "
        exit 1
    else
        log_success "端口检查通过"
    fi
}

start_services() {
    log_step "启动所有服务"
    
    log_info "启动 Notes Backend 应用..."
    systemctl start notes-backend
    sleep 10
    
    if systemctl is-active --quiet notes-backend; then
        log_success "Notes Backend 应用启动成功"
    else
        log_error "Notes Backend 应用启动失败"
        systemctl status notes-backend
        exit 1
    fi
    
    log_info "启动 HTTP 代理进行初始测试..."
    systemctl start notes-nginx-http
    sleep 5
    
    if systemctl is-active --quiet notes-nginx-http; then
        log_success "HTTP 代理启动成功"
        
        if curl -f http://127.0.0.1/health &>/dev/null; then
            log_success "HTTP 访问测试通过"
        else
            log_warn "HTTP 访问测试失败"
        fi
    else
        log_error "HTTP 代理启动失败"
        systemctl status notes-nginx-http
        exit 1
    fi
    
    log_success "所有服务启动完成"
}

obtain_real_certificate() {
    log_step "获取真实 SSL 证书"
    
    log_info "检查域名解析..."
    if nslookup $DOMAIN | grep -q "Address"; then
        log_success "域名解析正常"
    else
        log_warn "域名解析可能有问题，但继续尝试获取证书"
    fi
    
    systemctl stop notes-nginx-http
    
    log_info "正在获取 Let's Encrypt 证书..."
    if certbot certonly --standalone \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --domains $DOMAIN \
        --non-interactive; then
        
        log_success "SSL 证书获取成功"
        
        systemctl enable notes-nginx
        systemctl start notes-nginx
        
        if systemctl is-active --quiet notes-nginx; then
            log_success "HTTPS 代理启动成功"
            setup_certificate_renewal
        else
            log_warn "HTTPS 代理启动失败，回退到 HTTP"
            systemctl start notes-nginx-http
        fi
        
    else
        log_warn "SSL 证书获取失败，继续使用 HTTP"
        log_warn "请检查：1. 域名解析是否正确 2. 防火墙/安全组端口是否开放"
        
        systemctl start notes-nginx-http
    fi
}

setup_certificate_renewal() {
    log_info "设置证书自动续期..."
    
    cat > /usr/local/bin/renew-certificates.sh << EOF
systemctl stop notes-nginx 2>/dev/null || systemctl stop notes-nginx-http
certbot renew --quiet
if systemctl is-enabled notes-nginx &>/dev/null; then
    systemctl start notes-nginx
else
    systemctl start notes-nginx-http
fi
EOF
    
    chmod +x /usr/local/bin/renew-certificates.sh
    
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/renew-certificates.sh") | crontab -
    
    log_success "证书自动续期配置完成"
}

create_management_scripts() {
    log_step "创建管理脚本"
    
    cd $PROJECT_DIR
    
    cat > start.sh << EOF
echo "🚀 启动 Notes Backend 服务..."
systemctl start notes-backend

if systemctl is-enabled notes-nginx &>/dev/null; then
    systemctl start notes-nginx
    echo "✅ 服务已启动 (HTTPS)"
    echo "📱 访问地址: https://$DOMAIN"
else
    systemctl start notes-nginx-http
    echo "✅ 服务已启动 (HTTP)"
    echo "📱 访问地址: http://$DOMAIN"
fi

echo "🔍 状态检查: systemctl status notes-backend"
echo "🔍 获取 HTTPS: ./enable-https.sh"
EOF

    cat > stop.sh << 'EOF'
echo "🛑 停止 Notes Backend 服务..."
systemctl stop notes-nginx 2>/dev/null || true
systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-backend
echo "✅ 服务已停止"
EOF
    
    cat > restart.sh << 'EOF'
echo "🔄 重启 Notes Backend 服务..."
systemctl stop notes-nginx 2>/dev/null || true
systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-backend
sleep 3
systemctl start notes-backend
sleep 5

if systemctl is-enabled notes-nginx &>/dev/null; then
    systemctl start notes-nginx
    echo "✅ 服务已重启 (HTTPS)"
else
    systemctl start notes-nginx-http
    echo "✅ 服务已重启 (HTTP)"
fi
EOF

    cat > enable-https.sh << EOF
echo "🔒 启用 HTTPS..."

echo "检查域名解析..."
if ! nslookup $DOMAIN | grep -q "Address"; then
    echo "❌ 域名解析失败，请先配置域名解析"
    exit 1
fi

systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-nginx 2>/dev/null || true

echo "获取 SSL 证书..."
if certbot certonly --standalone \\
    --email $EMAIL \\
    --agree-tos \\
    --no-eff-email \\
    --domains $DOMAIN \\
    --non-interactive; then
    
    echo "✅ SSL 证书获取成功"
    
    systemctl enable notes-nginx
    systemctl disable notes-nginx-http 2>/dev/null || true
    systemctl start notes-nginx
    
    if systemctl is-active --quiet notes-nginx; then
        echo "✅ HTTPS 服务启动成功"
        echo "📱 访问地址: https://$DOMAIN"
    else
        echo "❌ HTTPS 服务启动失败，回退到 HTTP"
        systemctl start notes-nginx-http
    fi
else
    echo "❌ SSL 证书获取失败"
    echo "请检查："
    echo "1. 域名是否正确解析到此服务器"
    echo "2. 腾讯云安全组是否开放 80、443 端口"
    echo "3. 防火墙是否正确配置"
    
    systemctl start notes-nginx-http
fi
EOF
    
    cat > status.sh << EOF
echo "📊 Notes Backend 服务状态"
echo "================================"
echo "应用服务:"
systemctl status notes-backend --no-pager -l
echo ""
echo "Nginx 代理:"
if systemctl is-active --quiet notes-nginx; then
    echo "HTTPS 模式:"
    systemctl status notes-nginx --no-pager -l
elif systemctl is-active --quiet notes-nginx-http; then
    echo "HTTP 模式:"
    systemctl status notes-nginx-http --no-pager -l
else
    echo "代理服务未运行"
fi
echo ""
echo "应用进程:"
ps aux | grep notes-backend | grep -v grep
echo ""
echo "端口监听:"
netstat -tlnp | grep -E ":80|:443|:9191"
echo ""
echo "健康检查:"
if systemctl is-active --quiet notes-nginx; then
    curl -s https://$DOMAIN/health || echo "HTTPS 健康检查失败"
else
    curl -s http://$DOMAIN/health || echo "HTTP 健康检查失败"
fi
EOF
    
    cat > logs.sh << 'EOF'
echo "📝 Notes Backend 日志"
echo "================================"
echo "选择要查看的日志:"
echo "1. 应用日志"
echo "2. Nginx 日志"
echo "3. 系统日志"
echo "4. 所有日志"
read -p "请选择 (1-4): " choice

case $choice in
    1)
        echo "应用日志:"
        journalctl -u notes-backend -f --no-pager
        ;;
    2)
        echo "Nginx 日志:"
        docker logs -f notes-nginx 2>/dev/null || echo "Nginx 容器未运行"
        ;;
    3)
        echo "系统日志:"
        journalctl -f --no-pager
        ;;
    4)
        echo "所有相关日志:"
        journalctl -u notes-backend -u notes-nginx -u notes-nginx-http -f --no-pager
        ;;
    *)
        echo "无效选择"
        ;;
esac
EOF
    
    cat > update.sh << EOF
echo "🔄 更新 Notes Backend..."
cd $PROJECT_DIR

cp notes-backend notes-backend.backup.\$(date +%Y%m%d_%H%M%S)

export PATH=\$PATH:/usr/local/go/bin
export GOPROXY=https://goproxy.cn,direct

echo "📦 更新依赖..."
go mod download
go mod tidy

echo "🔨 重新编译..."
go build -ldflags="-w -s" -o notes-backend cmd/server/main.go

if [ \$? -eq 0 ]; then
    echo "✅ 编译成功，重启服务..."
    ./restart.sh
    echo "🎉 更新完成！"
else
    echo "❌ 编译失败，恢复备份..."
    mv notes-backend.backup.* notes-backend
fi
EOF
    
    chmod +x *.sh
    
    log_success "管理脚本创建完成"
}

verify_deployment() {
    log_step "验证部署"
    
    log_info "检查端口监听..."
    if netstat -tlnp | grep -q ":80\|:443\|:$APP_PORT"; then
        log_success "✅ 端口监听正常"
    else
        log_warn "⚠️ 部分端口可能未正常监听"
    fi
    
    log_info "检查服务状态..."
    BACKEND_ACTIVE=$(systemctl is-active notes-backend)
    NGINX_ACTIVE=$(systemctl is-active notes-nginx 2>/dev/null || systemctl is-active notes-nginx-http 2>/dev/null)
    
    if [ "$BACKEND_ACTIVE" = "active" ] && [ "$NGINX_ACTIVE" = "active" ]; then
        log_success "✅ 所有服务运行正常"
    else
        log_warn "⚠️ 部分服务可能未正常运行"
    fi
    
    log_info "检查应用健康状态..."
    sleep 5
    if curl -f http://127.0.0.1:$APP_PORT/health &>/dev/null; then
        log_success "✅ 应用健康检查通过"
    else
        log_warn "⚠️ 应用健康检查失败"
    fi
    
    log_info "检查代理访问..."
    if systemctl is-active --quiet notes-nginx; then
        if curl -f -k https://127.0.0.1/health &>/dev/null 2>&1; then
            log_success "✅ HTTPS 代理正常"
        else
            log_warn "⚠️ HTTPS 代理可能有问题"
        fi
    elif systemctl is-active --quiet notes-nginx-http; then
        if curl -f http://127.0.0.1/health &>/dev/null 2>&1; then
            log_success "✅ HTTP 代理正常"
        else
            log_warn "⚠️ HTTP 代理可能有问题"
        fi
    fi
}

show_deployment_result() {
    clear
    echo -e "${GREEN}"
    cat << 'EOF'
    🎉 部署完成！
    ===============================================
    
    ███████╗██╗   ██╗ ██████╗ ██████╗███████╗███████╗███████╗
    ██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝██╔════╝██╔════╝
    ███████╗██║   ██║██║     ██║     █████╗  ███████╗███████╗
    ╚════██║██║   ██║██║     ██║     ██╔══╝  ╚════██║╚════██║
    ███████║╚██████╔╝╚██████╗╚██████╗███████╗███████║███████║
    ╚══════╝ ╚═════╝  ╚═════╝ ╚═════╝╚══════╝╚══════╝╚══════╝
    
EOF
    echo -e "${NC}"
    
    if systemctl is-active --quiet notes-nginx; then
        CURRENT_MODE="HTTPS"
        ACCESS_URL="https://$DOMAIN"
    else
        CURRENT_MODE="HTTP"
        ACCESS_URL="http://$DOMAIN"
    fi
    
    echo -e "${CYAN}📱 访问信息:${NC}"
    echo -e "   当前模式: ${GREEN}$CURRENT_MODE${NC}"
    echo -e "   主站: ${GREEN}$ACCESS_URL${NC}"
    echo -e "   健康检查: ${GREEN}$ACCESS_URL/health${NC}"
    echo -e "   API 基础地址: ${GREEN}$ACCESS_URL/api${NC}"
    
    if [ "$CURRENT_MODE" = "HTTP" ]; then
        echo -e "\n${YELLOW}⚠️ 当前运行在 HTTP 模式${NC}"
        echo -e "   要启用 HTTPS，请运行: ${CYAN}cd $PROJECT_DIR && ./enable-https.sh${NC}"
        echo -e "   确保域名解析正确且安全组端口已开放"
    fi
    
    echo -e "\n${CYAN}🔧 管理命令:${NC}"
    echo -e "   启动服务: ${YELLOW}cd $PROJECT_DIR && ./start.sh${NC}"
    echo -e "   停止服务: ${YELLOW}cd $PROJECT_DIR && ./stop.sh${NC}"
    echo -e "   重启服务: ${YELLOW}cd $PROJECT_DIR && ./restart.sh${NC}"
    echo -e "   查看状态: ${YELLOW}cd $PROJECT_DIR && ./status.sh${NC}"
    echo -e "   查看日志: ${YELLOW}cd $PROJECT_DIR && ./logs.sh${NC}"
    echo -e "   更新应用: ${YELLOW}cd $PROJECT_DIR && ./update.sh${NC}"
    echo -e "   启用HTTPS: ${YELLOW}cd $PROJECT_DIR && ./enable-https.sh${NC}"
    
    echo -e "\n${CYAN}🖥️ 系统服务:${NC}"
    echo -e "   应用服务: ${YELLOW}systemctl {start|stop|restart|status} notes-backend${NC}"
    if [ "$CURRENT_MODE" = "HTTPS" ]; then
        echo -e "   代理服务: ${YELLOW}systemctl {start|stop|restart|status} notes-nginx${NC}"
    else
        echo -e "   代理服务: ${YELLOW}systemctl {start|stop|restart|status} notes-nginx-http${NC}"
    fi
    echo -e "   开机自启: ${GREEN}已启用${NC}"
    
    echo -e "\n${CYAN}🔒 安全组配置提醒:${NC}"
    echo -e "   请确保腾讯云安全组已开放以下端口："
    echo -e "   • ${GREEN}22${NC} (SSH)"
    echo -e "   • ${GREEN}80${NC} (HTTP)"
    echo -e "   • ${GREEN}443${NC} (HTTPS)"
    echo -e "   • ${GREEN}$APP_PORT${NC} (应用端口，可选)"
    
    echo -e "\n${CYAN}📁 重要目录:${NC}"
    echo -e "   项目目录: ${GREEN}$PROJECT_DIR${NC}"
    echo -e "   应用程序: ${GREEN}$PROJECT_DIR/notes-backend${NC}"
    echo -e "   配置文件: ${GREEN}$PROJECT_DIR/.env${NC}"
    echo -e "   上传目录: ${GREEN}$PROJECT_DIR/uploads${NC}"
    echo -e "   日志目录: ${GREEN}$PROJECT_DIR/logs${NC}"
    
    echo -e "\n${CYAN}🔐 安全信息:${NC}"
    echo -e "   JWT 密钥: ${YELLOW}$JWT_SECRET${NC}"
    echo -e "   数据库: ${GREEN}Vercel Postgres (已连接)${NC}"
    if [ "$CURRENT_MODE" = "HTTPS" ]; then
        echo -e "   SSL 证书: ${GREEN}Let's Encrypt (自动续期)${NC}"
    else
        echo -e "   SSL 证书: ${YELLOW}未配置 (使用 ./enable-https.sh 启用)${NC}"
    fi
    
    echo -e "\n${CYAN}🚀 API 端点示例:${NC}"
    echo -e "   注册用户: ${YELLOW}POST $ACCESS_URL/api/auth/register${NC}"
    echo -e "   用户登录: ${YELLOW}POST $ACCESS_URL/api/auth/login${NC}"
    echo -e "   获取笔记: ${YELLOW}GET $ACCESS_URL/api/notes${NC}"
    echo -e "   创建笔记: ${YELLOW}POST $ACCESS_URL/api/notes${NC}"
    
    echo -e "\n${CYAN}🛠️ 故障排除:${NC}"
    echo -e "   查看应用日志: ${YELLOW}journalctl -u notes-backend -f${NC}"
    echo -e "   查看代理日志: ${YELLOW}docker logs notes-nginx${NC}"
    echo -e "   检查端口占用: ${YELLOW}netstat -tlnp | grep -E ':80|:443|:9191'${NC}"
    echo -e "   检查域名解析: ${YELLOW}nslookup $DOMAIN${NC}"
    
    echo -e "\n${CYAN}📚 下一步操作:${NC}"
    echo -e "   1. 测试访问: ${GREEN}$ACCESS_URL${NC}"
    echo -e "   2. 检查安全组端口配置"
    if [ "$CURRENT_MODE" = "HTTP" ]; then
        echo -e "   3. 配置域名解析后运行 ./enable-https.sh"
    fi
    echo -e "   4. 使用 API 注册第一个用户"
    echo -e "   5. 创建第一条笔记"
    
    echo -e "\n${PURPLE}===============================================${NC}"
    echo -e "${GREEN}✨ Notes Backend 部署成功！${NC}"
    echo -e "${PURPLE}===============================================${NC}"
    
    echo -e "\n${CYAN}🔍 最终连接测试:${NC}"
    if curl -f $ACCESS_URL/health &>/dev/null; then
        echo -e "   ${GREEN}✅ 连接测试正常${NC}"
    else
        echo -e "   ${YELLOW}⚠️ 连接测试失败${NC}"
        echo -e "   ${YELLOW}请检查域名解析和安全组配置${NC}"
        echo -e "   ${YELLOW}本地测试: curl http://127.0.0.1/health${NC}"
    fi
}

cleanup_on_error() {
    log_error "部署过程中出现错误，正在清理..."
    
    systemctl stop notes-backend 2>/dev/null || true
    systemctl stop notes-nginx 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    
    docker stop notes-nginx 2>/dev/null || true
    docker rm notes-nginx 2>/dev/null || true
    
    log_info "请检查错误日志，修复问题后重新运行脚本"
    exit 1
}

main() {
    trap cleanup_on_error ERR
    
    check_root
    show_welcome
    collect_user_input
    detect_system
    install_dependencies
    setup_firewall
    create_project_structure
    compile_application
    create_configuration
    setup_ssl_certificate
    create_system_services
    handle_nginx_conflicts
    start_services
    obtain_real_certificate
    create_management_scripts
    verify_deployment
    show_deployment_result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi