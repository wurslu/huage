#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    Notes Backend 一键部署脚本                      ║"
    echo "║                      v1.0 - 生产环境部署                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "检测到您正在使用 root 用户运行脚本"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "已取消部署"
            exit 1
        fi
    fi
}

check_requirements() {
    print_info "检查系统要求..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_success "操作系统: Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        print_success "操作系统: macOS"
    else
        print_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
    
    local commands=("curl" "git")
    for cmd in "${commands[@]}"; do
        if command -v $cmd &> /dev/null; then
            print_success "$cmd 已安装"
        else
            print_error "$cmd 未安装，请先安装"
            exit 1
        fi
    done
}

install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装: $(docker --version)"
        return
    fi
    
    print_info "开始安装 Docker..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://get.docker.com | sh
        
        if [ "$EUID" -ne 0 ]; then
            sudo usermod -aG docker $USER
            print_warning "已将用户添加到 docker 组，请重新登录或运行 'newgrp docker'"
        fi
        
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        print_warning "请手动安装 Docker Desktop for Mac"
        print_info "下载地址: https://www.docker.com/products/docker-desktop"
        read -p "安装完成后按 Enter 继续..."
    fi
    
    print_success "Docker 安装完成"
}

install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose 已安装: $(docker-compose --version)"
        return
    fi
    
    print_info "开始安装 Docker Compose..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        local latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
        
        sudo curl -L "https://github.com/docker/compose/releases/download/${latest_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        print_info "Docker Desktop for Mac 已包含 Docker Compose"
    fi
    
    print_success "Docker Compose 安装完成"
}

collect_config() {
    print_info "配置生产环境参数..."
    echo
    
    echo -e "${BLUE}📊 数据库配置${NC}"
    echo "选择数据库模式:"
    echo "1) 本地 Docker PostgreSQL (推荐)"
    echo "2) Vercel PostgreSQL"
    echo "3) 自定义 PostgreSQL"
    
    while true; do
        read -p "请选择 (1-3): " db_choice
        case $db_choice in
            1)
                DB_MODE="local"
                collect_local_db_config
                break
                ;;
            2)
                DB_MODE="vercel"
                collect_vercel_db_config
                break
                ;;
            3)
                DB_MODE="custom"
                collect_custom_db_config
                break
                ;;
            *)
                print_warning "请输入 1、2 或 3"
                ;;
        esac
    done
    
    echo
    echo -e "${BLUE}🔐 安全配置${NC}"
    while true; do
        read -s -p "设置 JWT 密钥 (至少32位字符): " JWT_SECRET
        echo
        if [ ${#JWT_SECRET} -ge 32 ]; then
            break
        else
            print_warning "JWT 密钥长度至少需要32位字符"
        fi
    done
    
    echo
    echo -e "${BLUE}🌐 应用配置${NC}"
    read -p "前端域名 (例: https://xiaohua.tech): " FRONTEND_BASE_URL
    
    if [ -z "$FRONTEND_BASE_URL" ]; then
        FRONTEND_BASE_URL="https://xiaohua.tech"
    fi
    
    read -p "服务端口 (默认: 9191): " SERVER_PORT
    if [ -z "$SERVER_PORT" ]; then
        SERVER_PORT="9191"
    fi
    
    echo
    print_success "配置收集完成"
}

collect_local_db_config() {
    echo "本地 Docker PostgreSQL 配置:"
    read -p "数据库用户名 (默认: notes_user): " LOCAL_DB_USER
    read -s -p "数据库密码: " LOCAL_DB_PASSWORD
    echo
    read -p "数据库名称 (默认: notes_db): " LOCAL_DB_NAME
    
    LOCAL_DB_USER=${LOCAL_DB_USER:-notes_user}
    LOCAL_DB_NAME=${LOCAL_DB_NAME:-notes_db}
    
    if [ -z "$LOCAL_DB_PASSWORD" ]; then
        print_error "数据库密码不能为空"
        collect_local_db_config
        return
    fi
}

collect_vercel_db_config() {
    echo "Vercel PostgreSQL 配置:"
    echo "请在 Vercel Dashboard 创建 PostgreSQL 数据库并获取连接字符串"
    read -p "Vercel PostgreSQL URL: " VERCEL_POSTGRES_URL
    
    if [ -z "$VERCEL_POSTGRES_URL" ]; then
        print_error "Vercel PostgreSQL URL 不能为空"
        collect_vercel_db_config
        return
    fi
}

collect_custom_db_config() {
    echo "自定义 PostgreSQL 配置:"
    read -p "数据库连接 URL (可选): " CUSTOM_DB_URL
    
    if [ -z "$CUSTOM_DB_URL" ]; then
        read -p "数据库主机: " CUSTOM_DB_HOST
        read -p "数据库端口 (默认: 5432): " CUSTOM_DB_PORT
        read -p "数据库用户名: " CUSTOM_DB_USER
        read -s -p "数据库密码: " CUSTOM_DB_PASSWORD
        echo
        read -p "数据库名称: " CUSTOM_DB_NAME
        read -p "SSL 模式 (默认: require): " CUSTOM_DB_SSLMODE
        
        CUSTOM_DB_PORT=${CUSTOM_DB_PORT:-5432}
        CUSTOM_DB_SSLMODE=${CUSTOM_DB_SSLMODE:-require}
        
        if [ -z "$CUSTOM_DB_HOST" ] || [ -z "$CUSTOM_DB_USER" ] || [ -z "$CUSTOM_DB_PASSWORD" ] || [ -z "$CUSTOM_DB_NAME" ]; then
            print_error "所有数据库配置项都不能为空"
            collect_custom_db_config
            return
        fi
    fi
}

create_production_env() {
    print_info "创建生产环境配置文件..."
    
    cat > .env.production << EOF

DB_MODE=$DB_MODE
EOF

    case $DB_MODE in
        "local")
            cat >> .env.production << EOF
LOCAL_DB_HOST=postgres
LOCAL_DB_PORT=5432
LOCAL_DB_USER=$LOCAL_DB_USER
LOCAL_DB_PASSWORD=$LOCAL_DB_PASSWORD
LOCAL_DB_NAME=$LOCAL_DB_NAME
EOF
            ;;
        "vercel")
            cat >> .env.production << EOF
VERCEL_POSTGRES_URL=$VERCEL_POSTGRES_URL
EOF
            ;;
        "custom")
            if [ -n "$CUSTOM_DB_URL" ]; then
                cat >> .env.production << EOF
CUSTOM_DB_URL=$CUSTOM_DB_URL
CUSTOM_DB_SSLMODE=require
EOF
            else
                cat >> .env.production << EOF
CUSTOM_DB_HOST=$CUSTOM_DB_HOST
CUSTOM_DB_PORT=$CUSTOM_DB_PORT
CUSTOM_DB_USER=$CUSTOM_DB_USER
CUSTOM_DB_PASSWORD=$CUSTOM_DB_PASSWORD
CUSTOM_DB_NAME=$CUSTOM_DB_NAME
CUSTOM_DB_SSLMODE=$CUSTOM_DB_SSLMODE
EOF
            fi
            ;;
    esac

    cat >> .env.production << EOF

JWT_SECRET=$JWT_SECRET
SERVER_PORT=$SERVER_PORT
GIN_MODE=release
FRONTEND_BASE_URL=$FRONTEND_BASE_URL

UPLOAD_PATH=./uploads
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000

LOG_LEVEL=info
LOG_FILE=./logs/app.log
EOF

    print_success "生产环境配置文件创建完成"
}

create_directories() {
    print_info "创建项目目录结构..."
    
    mkdir -p uploads/{users,temp}
    mkdir -p logs
    mkdir -p backup
    mkdir -p nginx/ssl
    mkdir -p certbot/{www,conf}
    
    chmod -R 755 uploads/ logs/ backup/ nginx/ certbot/
    
    touch uploads/.gitkeep
    touch backup/.gitkeep
    
    print_success "目录结构创建完成"
}

check_port() {
    local port=$1
    if command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            print_warning "端口 $port 已被占用"
            return 1
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            print_warning "端口 $port 已被占用"
            return 1
        fi
    fi
    return 0
}

deploy_application() {
    print_info "开始部署应用..."
    
    if ! check_port $SERVER_PORT; then
        read -p "是否继续部署？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "已取消部署"
            exit 1
        fi
    fi
    
    if [ -f "docker-compose.yml" ]; then
        print_info "停止现有服务..."
        docker-compose down || true
    fi
    
    cp .env.production .env
    
    print_info "构建并启动服务..."
    docker-compose up -d --build
    
    print_info "等待服务启动..."
    sleep 15
    
    print_info "执行健康检查..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f http://localhost:$SERVER_PORT/health &> /dev/null; then
            print_success "服务启动成功！"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    
    print_error "服务启动失败，请检查日志"
    docker-compose logs
    return 1
}

configure_firewall() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        return
    fi
    
    print_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow $SERVER_PORT/tcp
        print_success "UFW 防火墙配置完成"
        
    elif command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=22/tcp
        sudo firewall-cmd --permanent --add-port=80/tcp
        sudo firewall-cmd --permanent --add-port=443/tcp
        sudo firewall-cmd --permanent --add-port=$SERVER_PORT/tcp
        sudo firewall-cmd --reload
        print_success "Firewalld 防火墙配置完成"
        
    else
        print_warning "未检测到防火墙管理工具，请手动配置防火墙"
    fi
}

show_deployment_info() {
    echo
    print_success "🎉 部署完成！"
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                           部署信息                                ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} 🌐 前端地址: ${BLUE}$FRONTEND_BASE_URL${NC}"
    echo -e "${GREEN}║${NC} 🔧 后端地址: ${BLUE}http://localhost:$SERVER_PORT${NC}"
    echo -e "${GREEN}║${NC} 🏥 健康检查: ${BLUE}http://localhost:$SERVER_PORT/health${NC}"
    echo -e "${GREEN}║${NC} �� 数据库模式: ${BLUE}$DB_MODE${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                         管理命令                                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} 查看日志: ${YELLOW}docker-compose logs -f${NC}"
    echo -e "${GREEN}║${NC} 重启服务: ${YELLOW}docker-compose restart${NC}"
    echo -e "${GREEN}║${NC} 停止服务: ${YELLOW}docker-compose down${NC}"
    echo -e "${GREEN}║${NC} 查看状态: ${YELLOW}docker-compose ps${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    if [[ "$FRONTEND_BASE_URL" == https* ]]; then
        print_warning "HTTPS 域名检测到，请配置 SSL 证书:"
        echo "1. 确保域名已解析到此服务器"
        echo "2. 配置 Nginx 反向代理"
        echo "3. 使用 Let's Encrypt 获取 SSL 证书"
    fi
    
    echo
    print_info "日志文件位置:"
    echo "- 应用日志: ./logs/app.log"
    echo "- Docker 日志: docker-compose logs"
    
    echo
    print_success "感谢使用 Notes Backend！"
}

main() {
    print_header
    
    if [ ! -f "go.mod" ] || [ ! -f "docker-compose.yml" ]; then
        print_error "请在项目根目录运行此脚本"
        exit 1
    fi
    
    check_root
    check_requirements
    install_docker
    install_docker_compose
    collect_config
    create_production_env
    create_directories
    deploy_application
    configure_firewall
    show_deployment_info
}

trap 'print_error "部署过程中发生错误，请检查上面的错误信息"; exit 1' ERR

main "$@"
