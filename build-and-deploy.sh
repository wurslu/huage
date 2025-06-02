#!/bin/bash

# =============================================================================
# Notes Backend 构建并部署脚本
# 用于从源码构建 Docker 镜像并一键部署
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

# 配置
PROJECT_NAME="notes-backend"
DOCKER_IMAGE="notes-backend:latest"
DEPLOY_SCRIPT_URL="https://raw.githubusercontent.com/your-repo/notes-backend/main/deploy.sh"

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${PURPLE}[SUCCESS]${NC} $1"; }

show_usage() {
    echo -e "${CYAN}用法:${NC}"
    echo "  $0 [选项]"
    echo ""
    echo -e "${CYAN}选项:${NC}"
    echo "  --build-only     仅构建 Docker 镜像，不部署"
    echo "  --deploy-only    仅部署（假设镜像已存在）"
    echo "  --skip-tests     跳过测试"
    echo "  --help          显示此帮助信息"
    echo ""
    echo -e "${CYAN}示例:${NC}"
    echo "  $0                    # 完整构建和部署"
    echo "  $0 --build-only       # 仅构建镜像"
    echo "  $0 --deploy-only      # 仅部署"
}

# 检查必要文件
check_prerequisites() {
    log_step "检查前置条件"
    
    # 检查是否在项目根目录
    if [ ! -f "Dockerfile" ]; then
        log_error "未找到 Dockerfile，请在项目根目录运行此脚本"
        exit 1
    fi
    
    if [ ! -f "go.mod" ]; then
        log_error "未找到 go.mod，请确保在 Go 项目根目录"
        exit 1
    fi
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 运行测试
run_tests() {
    if [ "$SKIP_TESTS" = "true" ]; then
        log_warn "跳过测试"
        return
    fi
    
    log_step "运行测试"
    
    if command -v go &> /dev/null; then
        log_info "运行 Go 测试..."
        go test -v ./... || {
            log_error "测试失败"
            exit 1
        }
        log_success "测试通过"
    else
        log_warn "Go 未安装，跳过本地测试"
    fi
}

# 构建 Docker 镜像
build_docker_image() {
    log_step "构建 Docker 镜像"
    
    # 显示构建信息
    log_info "镜像名称: $DOCKER_IMAGE"
    log_info "构建上下文: $(pwd)"
    
    # 构建镜像
    log_info "开始构建镜像..."
    docker build \
        --tag $DOCKER_IMAGE \
        --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --build-arg GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
        --build-arg VERSION="$(git describe --tags --always 2>/dev/null || echo 'dev')" \
        . || {
        log_error "Docker 镜像构建失败"
        exit 1
    }
    
    log_success "Docker 镜像构建成功"
    
    # 显示镜像信息
    log_info "镜像信息:"
    docker images $DOCKER_IMAGE
}

# 测试镜像
test_docker_image() {
    log_step "测试 Docker 镜像"
    
    # 创建临时容器测试
    log_info "启动测试容器..."
    CONTAINER_ID=$(docker run -d \
        --name notes-test \
        -p 19191:9191 \
        -e JWT_SECRET="test-secret" \
        -e VERCEL_POSTGRES_URL="postgresql://test:test@localhost:5432/test?sslmode=disable" \
        $DOCKER_IMAGE)
    
    # 等待容器启动
    sleep 10
    
    # 健康检查
    if curl -f http://localhost:19191/health &>/dev/null; then
        log_success "镜像测试通过"
    else
        log_error "镜像测试失败"
        docker logs notes-test
        docker stop notes-test && docker rm notes-test
        exit 1
    fi
    
    # 清理测试容器
    docker stop notes-test && docker rm notes-test
}

# 优化镜像
optimize_image() {
    log_step "优化镜像"
    
    # 显示镜像大小
    IMAGE_SIZE=$(docker images $DOCKER_IMAGE --format "table {{.Size}}" | tail -n1)
    log_info "镜像大小: $IMAGE_SIZE"
    
    # 清理悬挂镜像
    log_info "清理构建缓存..."
    docker image prune -f
    
    # 如果镜像过大，给出建议
    SIZE_MB=$(docker images $DOCKER_IMAGE --format "{{.Size}}" | sed 's/MB//' | sed 's/GB/*1000/' | bc 2>/dev/null || echo "0")
    if [ "$SIZE_MB" -gt 500 ]; then
        log_warn "镜像较大 ($IMAGE_SIZE)，建议优化 Dockerfile"
    fi
}

# 下载部署脚本
download_deploy_script() {
    log_step "准备部署脚本"
    
    # 如果本地没有部署脚本，从远程下载
    if [ ! -f "deploy.sh" ]; then
        log_info "下载部署脚本..."
        curl -fsSL $DEPLOY_SCRIPT_URL -o deploy.sh || {
            log_error "下载部署脚本失败"
            exit 1
        }
    fi
    
    chmod +x deploy.sh
    log_success "部署脚本准备完成"
}

# 创建部署包
create_deployment_package() {
    log_step "创建部署包"
    
    PACKAGE_NAME="notes-backend-deploy-$(date +%Y%m%d-%H%M%S)"
    PACKAGE_DIR="/tmp/$PACKAGE_NAME"
    
    mkdir -p $PACKAGE_DIR
    
    # 保存镜像
    log_info "导出 Docker 镜像..."
    docker save $DOCKER_IMAGE | gzip > $PACKAGE_DIR/notes-backend-image.tar.gz
    
    # 复制部署文件
    cp deploy.sh $PACKAGE_DIR/
    cp docker-compose.yml $PACKAGE_DIR/ 2>/dev/null || true
    cp -r nginx $PACKAGE_DIR/ 2>/dev/null || true
    
    # 创建部署说明
    cat > $PACKAGE_DIR/README.md << EOF
# Notes Backend 部署包

## 快速部署

1. 上传此目录到服务器
2. 加载 Docker 镜像:
   \`\`\`bash
   docker load < notes-backend-image.tar.gz
   \`\`\`
3. 运行部署脚本:
   \`\`\`bash
   chmod +x deploy.sh
   ./deploy.sh
   \`\`\`

## 文件说明

- \`notes-backend-image.tar.gz\`: Docker 镜像文件
- \`deploy.sh\`: 一键部署脚本
- \`docker-compose.yml\`: Docker Compose 配置（如果存在）
- \`nginx/\`: Nginx 配置文件（如果存在）

创建时间: $(date)
镜像版本: $DOCKER_IMAGE
EOF
    
    # 创建压缩包
    cd /tmp
    tar -czf $PACKAGE_NAME.tar.gz $PACKAGE_NAME
    
    log_success "部署包创建完成: /tmp/$PACKAGE_NAME.tar.gz"
    echo -e "${CYAN}部署包路径:${NC} /tmp/$PACKAGE_NAME.tar.gz"
}

# 运行部署
run_deployment() {
    log_step "开始部署"
    
    if [ ! -f "deploy.sh" ]; then
        download_deploy_script
    fi
    
    # 修改部署脚本中的镜像名称
    sed -i "s|DOCKER_IMAGE=.*|DOCKER_IMAGE=\"$DOCKER_IMAGE\"|g" deploy.sh
    
    log_info "运行部署脚本..."
    bash deploy.sh
}

# 显示完成信息
show_completion() {
    echo -e "\n${GREEN}"
    cat << 'EOF'
    🎉 构建和部署完成！
    ===================================
EOF
    echo -e "${NC}"
    
    if [ "$BUILD_ONLY" = "true" ]; then
        echo -e "${CYAN}✅ 镜像构建完成${NC}"
        echo -e "镜像名称: ${GREEN}$DOCKER_IMAGE${NC}"
        echo -e "\n${CYAN}下一步操作:${NC}"
        echo -e "1. 推送镜像到仓库: ${YELLOW}docker push $DOCKER_IMAGE${NC}"
        echo -e "2. 在服务器上拉取镜像: ${YELLOW}docker pull $DOCKER_IMAGE${NC}"
        echo -e "3. 运行部署脚本: ${YELLOW}./deploy.sh${NC}"
    elif [ "$DEPLOY_ONLY" = "true" ]; then
        echo -e "${CYAN}✅ 部署完成${NC}"
    else
        echo -e "${CYAN}✅ 完整流程完成${NC}"
        echo -e "镜像: ${GREEN}$DOCKER_IMAGE${NC}"
        echo -e "部署: ${GREEN}完成${NC}"
    fi
    
    echo -e "\n${CYAN}有用的命令:${NC}"
    echo -e "查看镜像: ${YELLOW}docker images $DOCKER_IMAGE${NC}"
    echo -e "查看容器: ${YELLOW}docker ps${NC}"
    echo -e "查看日志: ${YELLOW}docker-compose logs -f${NC}"
}

# 主函数
main() {
    # 解析参数
    BUILD_ONLY=false
    DEPLOY_ONLY=false
    SKIP_TESTS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            --deploy-only)
                DEPLOY_ONLY=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 显示开始信息
    echo -e "${CYAN}🚀 Notes Backend 构建部署工具${NC}"
    echo -e "================================"
    
    # 执行相应操作
    if [ "$DEPLOY_ONLY" = "true" ]; then
        log_info "仅部署模式"
        check_prerequisites
        run_deployment
    elif [ "$BUILD_ONLY" = "true" ]; then
        log_info "仅构建模式"
        check_prerequisites
        run_tests
        build_docker_image
        test_docker_image
        optimize_image
        create_deployment_package
    else
        log_info "完整构建部署模式"
        check_prerequisites
        run_tests
        build_docker_image
        test_docker_image
        optimize_image
        run_deployment
    fi
    
    show_completion
}

# 错误处理
cleanup_on_error() {
    log_error "构建部署过程中出现错误"
    
    # 清理可能的测试容器
    docker stop notes-test 2>/dev/null && docker rm notes-test 2>/dev/null || true
    
    exit 1
}

# 设置错误处理
trap cleanup_on_error ERR

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi