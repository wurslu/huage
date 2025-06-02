#!/bin/bash

# deploy.sh - CentOS 服务器一键部署脚本

echo "🚀 Notes Backend CentOS 部署脚本"
echo "=================================="

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 安装 Docker
install_docker() {
    echo "📦 安装 Docker..."
    
    # 卸载旧版本
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    
    # 安装依赖
    yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # 添加 Docker 仓库
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装 Docker
    yum install -y docker-ce docker-ce-cli containerd.io
    
    # 启动 Docker
    systemctl start docker
    systemctl enable docker
    
    echo "✅ Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    echo "📦 安装 Docker Compose..."
    
    # 下载 Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    echo "✅ Docker Compose 安装完成"
}

# 安装其他必要工具
install_tools() {
    echo "📦 安装必要工具..."
    
    # 更新系统
    yum update -y
    
    # 安装基础工具
    yum install -y git wget curl vim nano firewalld
    
    echo "✅ 基础工具安装完成"
}

# 配置防火墙
setup_firewall() {
    echo "🔥 配置防火墙..."
    
    # 启动防火墙
    systemctl start firewalld
    systemctl enable firewalld
    
    # 开放端口
    firewall-cmd --permanent --add-port=80/tcp    # HTTP
    firewall-cmd --permanent --add-port=443/tcp   # HTTPS
    firewall-cmd --permanent --add-port=9191/tcp  # 应用端口
    firewall-cmd --permanent --add-port=22/tcp    # SSH
    
    # 重载配置
    firewall-cmd --reload
    
    echo "✅ 防火墙配置完成"
}

# 创建项目目录
setup_project() {
    echo "📁 创建项目目录..."
    
    # 创建目录
    mkdir -p /opt/notes-backend
    cd /opt/notes-backend
    
    # 创建必要的子目录
    mkdir -p uploads logs nginx/ssl
    
    # 设置权限
    chown -R 1001:1001 uploads logs
    chmod -R 755 uploads logs
    
    echo "✅ 项目目录创建完成"
}

# 创建部署用的 docker-compose.yml
create_docker_compose() {
    cat > /opt/notes-backend/docker-compose.yml << 'EOF'
version: "3.8"

services:
  app:
    image: your-registry/notes-backend:latest  # 替换为你的镜像
    container_name: notes-backend
    restart: unless-stopped
    ports:
      - "9191:9191"
    environment:
      - DB_MODE=vercel
      - VERCEL_POSTGRES_URL=${VERCEL_POSTGRES_URL}
      - JWT_SECRET=${JWT_SECRET}
      - SERVER_PORT=9191
      - GIN_MODE=release
      - FRONTEND_BASE_URL=${FRONTEND_BASE_URL}
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
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9191/health"]
      interval: 30s
      timeout: 10s
      retries: 3

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
    depends_on:
      - app
    networks:
      - notes-network

networks:
  notes-network:
    driver: bridge
EOF

    echo "✅ Docker Compose 配置创建完成"
}

# 创建 Nginx 配置
create_nginx_config() {
    cat > /opt/notes-backend/nginx/nginx.conf << 'EOF'
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
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # HTTP 重定向到 HTTPS
    server {
        listen 80;
        server_name huage.api.withgo.cn;
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        location / {
            return 301 https://$server_name$request_uri;
        }
    }
    
    # HTTPS 主站
    server {
        listen 443 ssl http2;
        server_name huage.api.withgo.cn;
        
        # SSL 配置
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers on;
        
        # API 代理
        location / {
            proxy_pass http://app:9191;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }
    }
}
EOF

    echo "✅ Nginx 配置创建完成"
}

# 创建环境变量模板
create_env_template() {
    cat > /opt/notes-backend/.env.example << 'EOF'
# 数据库配置 (从 Vercel 控制台复制)
VERCEL_POSTGRES_URL="postgresql://user:password@host:5432/database?sslmode=require"

# 应用配置
JWT_SECRET="your-super-secret-jwt-key-change-this-in-production"
FRONTEND_BASE_URL="https://huage.api.withgo.cn"

# 文件上传配置
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000
EOF

    echo "✅ 环境变量模板创建完成"
    echo "⚠️  请编辑 /opt/notes-backend/.env 文件，填入你的配置"
}

# 创建管理脚本
create_management_scripts() {
    # 启动脚本
    cat > /opt/notes-backend/start.sh << 'EOF'
#!/bin/bash
echo "🚀 启动 Notes Backend..."
cd /opt/notes-backend
docker-compose up -d
echo "✅ 服务已启动"
echo "📱 访问地址: https://huage.api.withgo.cn"
EOF

    # 停止脚本
    cat > /opt/notes-backend/stop.sh << 'EOF'
#!/bin/bash
echo "🛑 停止 Notes Backend..."
cd /opt/notes-backend
docker-compose down
echo "✅ 服务已停止"
EOF

    # 重启脚本
    cat > /opt/notes-backend/restart.sh << 'EOF'
#!/bin/bash
echo "🔄 重启 Notes Backend..."
cd /opt/notes-backend
docker-compose down
docker-compose pull
docker-compose up -d
echo "✅ 服务已重启"
EOF

    # 查看日志脚本
    cat > /opt/notes-backend/logs.sh << 'EOF'
#!/bin/bash
echo "📝 查看 Notes Backend 日志..."
cd /opt/notes-backend
docker-compose logs -f --tail=50
EOF

    # 设置执行权限
    chmod +x /opt/notes-backend/*.sh
    
    echo "✅ 管理脚本创建完成"
}

# SSL 证书设置
setup_ssl() {
    echo "🔒 设置 SSL 证书..."
    
    # 安装 Certbot
    yum install -y epel-release
    yum install -y certbot python3-certbot-nginx
    
    echo "📝 SSL 证书设置完成"
    echo "🔗 获取证书命令: certbot --nginx -d huage.api.withgo.cn"
}

# 创建系统服务
create_systemd_service() {
    cat > /etc/systemd/system/notes-backend.service << 'EOF'
[Unit]
Description=Notes Backend
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/notes-backend
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    # 重载 systemd
    systemctl daemon-reload
    systemctl enable notes-backend
    
    echo "✅ 系统服务创建完成"
    echo "🔧 管理命令:"
    echo "   systemctl start notes-backend    # 启动服务"
    echo "   systemctl stop notes-backend     # 停止服务"
    echo "   systemctl status notes-backend   # 查看状态"
}

# 主安装函数
main() {
    echo "开始安装 Notes Backend 到 CentOS..."
    
    install_tools
    install_docker
    install_docker_compose
    setup_firewall
    setup_project
    create_docker_compose
    create_nginx_config
    create_env_template
    create_management_scripts
    setup_ssl
    create_systemd_service
    
    echo ""
    echo "🎉 安装完成！"
    echo "=================================="
    echo "📁 项目目录: /opt/notes-backend"
    echo "⚙️  下一步操作:"
    echo "   1. 编辑 /opt/notes-backend/.env 文件"
    echo "   2. 上传 SSL 证书到 /opt/notes-backend/nginx/ssl/"
    echo "   3. 运行: cd /opt/notes-backend && ./start.sh"
    echo ""
    echo "🔧 常用命令:"
    echo "   cd /opt/notes-backend && ./start.sh     # 启动服务"
    echo "   cd /opt/notes-backend && ./stop.sh      # 停止服务"
    echo "   cd /opt/notes-backend && ./restart.sh   # 重启服务"
    echo "   cd /opt/notes-backend && ./logs.sh      # 查看日志"
    echo "=================================="
}

# 执行安装
main