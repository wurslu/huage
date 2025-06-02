#!/bin/bash

# =============================================================================
# Notes Backend 快速启动脚本
# 自动检测环境并执行相应的部署操作
# =============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${PURPLE}[SUCCESS]${NC} $1"; }

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    🚀 Notes Backend 快速启动工具
    ========================================
    
    这个脚本会自动检测你的环境并选择最佳的部署方式：
    📦 如果在开发环境，会构建并部署
    🖥️  如果在生产服务器，会直接部署
    🔧 自动处理所有依赖和配置
    
EOF
    echo -e "${NC}"
}

# 检测环境
detect_environment() {
    log_step "检测环境"
    
    # 检查是否有源码
    if [ -f "Dockerfile" ] && [ -f "go.mod" ]; then
        ENV_TYPE="development"
        log_info "检测到开发环境（有源码）"
    elif [ -f "/opt/notes-backend/docker-compose.yml" ]; then
        ENV_TYPE="production"
        log_info "检测到生产环境（已部署）"
    else
        ENV_TYPE="fresh"
        log_info "检测到全新环境"
    fi
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        NEED_SUDO=true
        log_warn "非 root 用户，部分操作可能需要 sudo"
    else
        NEED_SUDO=false
        log_info "Root 用户，权限充足"
    fi
    
    # 检查 Docker
    if command -v docker &> /dev/null; then
        DOCKER_AVAILABLE=true
        log_info "Docker 可用"
    else
        DOCKER_AVAILABLE=false
        log_warn "Docker 未安装"
    fi
}

# 显示环境信息和选项
show_options() {
    echo -e "\n${CYAN}=== 环境信息 ===${NC}"
    echo -e "环境类型: ${GREEN}$ENV_TYPE${NC}"
    echo -e "用户权限: ${GREEN}$([ "$NEED_SUDO" = "true" ] && echo "普通用户" || echo "管理员")${NC}"
    echo -e "Docker: ${GREEN}$([ "$DOCKER_AVAILABLE" = "true" ] && echo "已安装" || echo "未安装")${NC}"
    
    echo -e "\n${CYAN}=== 可用操作 ===${NC}"
    case $ENV_TYPE in
        "development")
            echo -e "${YELLOW}1.${NC} 构建并部署到本机"
            echo -e "${YELLOW}2.${NC} 仅构建 Docker 镜像"
            echo -e "${YELLOW}3.${NC} 生成部署包"
            echo -e "${YELLOW}4.${NC} 本地开发运行"
            ;;
        "production")
            echo -e "${YELLOW}1.${NC} 重新部署"
            echo -e "${YELLOW}2.${NC} 更新服务"
            echo -e "${YELLOW}3.${NC} 查看状态"
            echo -e "${YELLOW}4.${NC} 查看日志"
            ;;
        "fresh")
            echo -e "${YELLOW}1.${NC} 完整安装部署"
            echo -e "${YELLOW}2.${NC} 仅安装 Docker"
            echo -e "${YELLOW}3.${NC} 下载项目代码"
            ;;
    esac
    echo -e "${YELLOW}0.${NC} 退出"
    
    echo -e "\n${CYAN}请选择操作 (0-4):${NC}"
    read -p "> " CHOICE
}

# 开发环境操作
handle_development() {
    case $CHOICE in
        1)
            log_step "构建并部署到本机"
            ./build-and-deploy.sh || {
                log_error "构建部署脚本不存在，尝试下载..."
                download_scripts
                ./build-and-deploy.sh
            }
            ;;
        2)
            log_step "仅构建 Docker 镜像"
            ./build-and-deploy.sh --build-only || {
                log_info "使用基础 Docker 构建..."
                docker build -t notes-backend:latest .
            }
            ;;
        3)
            log_step "生成部署包"
            ./build-and-deploy.sh --build-only
            create_quick_deploy_package
            ;;
        4)
            log_step "本地开发运行"
            run_local_development
            ;;
        0)
            log_info "退出"
            exit 0
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 生产环境操作
handle_production() {
    cd /opt/notes-backend
    case $CHOICE in
        1)
            log_step "重新部署"
            ./restart.sh
            ;;
        2)
            log_step "更新服务"
            docker-compose pull
            docker-compose up -d
            ;;
        3)
            log_step "查看状态"
            ./status.sh
            ;;
        4)
            log_step "查看日志"
            ./logs.sh
            ;;
        0)
            log_info "退出"
            exit 0
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 全新环境操作
handle_fresh() {
    case $CHOICE in
        1)
            log_step "完整安装部署"
            install_full_deployment
            ;;
        2)
            log_step "仅安装 Docker"
            install_docker_only
            ;;
        3)
            log_step "下载项目代码"
            download_project_code
            ;;
        0)
            log_info "退出"
            exit 0
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
}

# 下载部署脚本
download_scripts() {
    log_info "下载部署脚本..."
    
    # 这里你需要替换为实际的脚本 URL
    SCRIPT_BASE_URL="https://raw.githubusercontent.com/your-repo/notes-backend/main"
    
    curl -fsSL $SCRIPT_BASE_URL/deploy.sh -o deploy.sh
    curl -fsSL $SCRIPT_BASE_URL/build-and-deploy.sh -o build-and-deploy.sh
    
    chmod +x deploy.sh build-and-deploy.sh
    log_success "脚本下载完成"
}

# 本地开发运行
run_local_development() {
    log_info "启动本地开发环境..."
    
    # 检查是否有 .env 文件
    if [ ! -f ".env" ]; then
        log_info "创建开发环境配置..."
        cat > .env << 'EOF'
# 开发环境配置
DB_MODE=local
LOCAL_DB_HOST=localhost
LOCAL_DB_PORT=5432
LOCAL_DB_USER=notes_user
LOCAL_DB_PASSWORD=notes_password
LOCAL_DB_NAME=notes_db
JWT_SECRET=dev-secret-change-in-production
SERVER_PORT=9191
GIN_MODE=debug
FRONTEND_BASE_URL=http://localhost:9191
EOF
    fi
    
    # 检查 Go 环境
    if command -v go &> /dev/null; then
        log_info "使用 Go 直接运行..."
        go run cmd/server/main.go
    else
        log_info "使用 Docker 运行开发环境..."
        docker-compose -f docker-compose.dev.yml up --build
    fi
}

# 创建快速部署包
create_quick_deploy_package() {
    log_info "创建快速部署包..."
    
    PACKAGE_NAME="notes-backend-quick-deploy-$(date +%Y%m%d-%H%M%S)"
    mkdir -p /tmp/$PACKAGE_NAME
    
    # 保存镜像
    docker save notes-backend:latest | gzip > /tmp/$PACKAGE_NAME/image.tar.gz
    
    # 创建快速部署脚本
    cat > /tmp/$PACKAGE_NAME/quick-deploy.sh << 'EOF'
#!/bin/bash
echo "🚀 Notes Backend 快速部署"
echo "========================="

# 加载镜像
echo "📦 加载 Docker 镜像..."
docker load < image.tar.gz

# 运行一键部署
echo "🔧 开始部署..."
curl -fsSL https://raw.githubusercontent.com/your-repo/notes-backend/main/deploy.sh | bash

echo "✅ 部署完成！"
EOF
    
    chmod +x /tmp/$PACKAGE_NAME/quick-deploy.sh
    
    # 打包
    cd /tmp
    tar -czf $PACKAGE_NAME.tar.gz $PACKAGE_NAME
    
    log_success "快速部署包创建完成: /tmp/$PACKAGE_NAME.tar.gz"
    echo -e "${CYAN}上传到服务器后，解压并运行 quick-deploy.sh 即可${NC}"
}

# 完整安装部署
install_full_deployment() {
    log_info "开始完整安装部署..."
    
    if [ "$NEED_SUDO" = "true" ]; then
        log_error "需要 root 权限进行完整部署"
        echo -e "${CYAN}请使用以下命令获取 root 权限后重新运行:${NC}"
        echo -e "${YELLOW}sudo su -${NC}"
        echo -e "${YELLOW}curl -fsSL https://your-domain.com/quick-start.sh | bash${NC}"
        exit 1
    fi
    
    # 下载并运行完整部署脚本
    curl -fsSL https://raw.githubusercontent.com/your-repo/notes-backend/main/deploy.sh | bash
}

# 仅安装 Docker
install_docker_only() {
    log_info "安装 Docker..."
    
    if [ "$NEED_SUDO" = "true" ]; then
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
    
    # 检测操作系统
    if [ -f /etc/redhat-release ]; then
        # CentOS
        $SUDO_CMD apt-get update
        $SUDO_CMD apt-get install -y docker-ce docker-ce-cli containerd.io
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    # 启动 Docker
    $SUDO_CMD systemctl start docker
    $SUDO_CMD systemctl enable docker
    
    # 安装 Docker Compose
    $SUDO_CMD curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    $SUDO_CMD chmod +x /usr/local/bin/docker-compose
    
    log_success "Docker 安装完成"
}

# 下载项目代码
download_project_code() {
    log_info "下载项目代码..."
    
    if ! command -v git &> /dev/null; then
        log_info "安装 Git..."
        if [ -f /etc/redhat-release ]; then
            yum install -y git
        else
            apt-get update && apt-get install -y git
        fi
    fi
    
    # 克隆项目
    git clone https://github.com/your-repo/notes-backend.git
    cd notes-backend
    
    log_success "项目代码下载完成"
    log_info "进入 notes-backend 目录后可以重新运行此脚本"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}Notes Backend 快速启动工具${NC}"
    echo -e "================================"
    echo ""
    echo -e "${CYAN}用法:${NC}"
    echo "  $0 [选项]"
    echo ""
    echo -e "${CYAN}选项:${NC}"
    echo "  --auto          自动模式（跳过交互）"
    echo "  --dev           开发模式"
    echo "  --prod          生产模式"
    echo "  --help          显示帮助"
    echo ""
    echo -e "${CYAN}自动检测逻辑:${NC}"
    echo "  1. 如果当前目录有 Dockerfile 和 go.mod → 开发环境"
    echo "  2. 如果 /opt/notes-backend 存在 → 生产环境"
    echo "  3. 否则 → 全新环境"
    echo ""
    echo -e "${CYAN}快速开始:${NC}"
    echo "  开发者: 在项目根目录运行 $0"
    echo "  服务器: 直接运行 $0 进行一键部署"
}

# 自动模式
run_auto_mode() {
    detect_environment
    
    case $ENV_TYPE in
        "development")
            log_info "自动模式：构建并部署"
            ./build-and-deploy.sh 2>/dev/null || {
                log_info "下载构建脚本..."
                download_scripts
                ./build-and-deploy.sh
            }
            ;;
        "production")
            log_info "自动模式：更新生产环境"
            cd /opt/notes-backend
            docker-compose pull && docker-compose up -d
            ;;
        "fresh")
            log_info "自动模式：全新部署"
            if [ "$NEED_SUDO" = "false" ]; then
                install_full_deployment
            else
                log_error "自动模式需要 root 权限"
                exit 1
            fi
            ;;
    esac
}

# 开发模式
run_dev_mode() {
    if [ ! -f "Dockerfile" ]; then
        log_error "开发模式需要在项目根目录运行"
        exit 1
    fi
    
    log_info "开发模式：本地运行"
    run_local_development
}

# 生产模式
run_prod_mode() {
    if [ "$NEED_SUDO" = "false" ]; then
        install_full_deployment
    else
        log_error "生产模式需要 root 权限"
        exit 1
    fi
}

# 检查更新
check_updates() {
    log_info "检查脚本更新..."
    
    # 获取最新版本信息（这里需要实现版本检查逻辑）
    CURRENT_VERSION="1.0.0"
    # LATEST_VERSION=$(curl -s https://api.github.com/repos/your-repo/notes-backend/releases/latest | grep tag_name | cut -d '"' -f 4)
    
    # if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    #     log_warn "发现新版本: $LATEST_VERSION (当前: $CURRENT_VERSION)"
    #     echo -e "${CYAN}是否更新到最新版本? (y/N):${NC}"
    #     read -p "> " UPDATE_CONFIRM
    #     if [[ "$UPDATE_CONFIRM" =~ ^[Yy]$ ]]; then
    #         curl -fsSL https://raw.githubusercontent.com/your-repo/notes-backend/main/quick-start.sh -o /tmp/quick-start-new.sh
    #         chmod +x /tmp/quick-start-new.sh
    #         exec /tmp/quick-start-new.sh "$@"
    #     fi
    # fi
}

# 错误处理
handle_error() {
    log_error "执行过程中出现错误"
    echo -e "${CYAN}常见问题排查:${NC}"
    echo -e "1. 检查网络连接"
    echo -e "2. 确认权限足够"
    echo -e "3. 查看详细错误信息"
    echo -e "4. 尝试手动执行相关命令"
    exit 1
}

# 主函数
main() {
    # 设置错误处理
    trap handle_error ERR
    
    # 解析参数
    AUTO_MODE=false
    DEV_MODE=false
    PROD_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --dev)
                DEV_MODE=true
                shift
                ;;
            --prod)
                PROD_MODE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查更新
    check_updates
    
    # 根据模式执行
    if [ "$AUTO_MODE" = "true" ]; then
        run_auto_mode
    elif [ "$DEV_MODE" = "true" ]; then
        run_dev_mode
    elif [ "$PROD_MODE" = "true" ]; then
        run_prod_mode
    else
        # 交互模式
        show_welcome
        detect_environment
        show_options
        
        case $ENV_TYPE in
            "development")
                handle_development
                ;;
            "production")
                handle_production
                ;;
            "fresh")
                handle_fresh
                ;;
        esac
    fi
    
    log_success "操作完成！"
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fiCMD yum update -y
        $SUDO_CMD yum install -y yum-utils
        $SUDO_CMD yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        $SUDO_CMD yum install -y docker-ce docker-ce-cli containerd.io
    elif [ -f /etc/debian_version ]; then
        # Ubuntu/Debian
        $SUDO_CMD apt-get update
        $SUDO_CMD apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO_CMD gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | $SUDO_CMD tee /etc/apt/sources.list.d/docker.list > /dev/null
        $SUDO_