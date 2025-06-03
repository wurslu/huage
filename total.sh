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
DEFAULT_REPO="https://github.com/wurslu/huage"

DB_TYPE=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
VERCEL_POSTGRES_URL=""
CUSTOM_DB_HOST=""
CUSTOM_DB_PORT=""
CUSTOM_DB_USER=""
CUSTOM_DB_PASSWORD=""
CUSTOM_DB_NAME=""

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        echo "运行: sudo bash $0"
        exit 1
    fi
}

show_welcome() {
    clear
    echo -e "${CYAN}"
    cat <<'EOF'
    ███╗   ██╗ ██████╗ ████████╗███████╗███████╗
    ████╗  ██║██╔═══██╗╚══██╔══╝██╔════╝██╔════╝
    ██╔██╗ ██║██║   ██║   ██║   █████╗  ███████╗
    ██║╚██╗██║██║   ██║   ██║   ██╔══╝  ╚════██║
    ██║ ╚████║╚██████╔╝   ██║   ███████╗███████║
    ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚══════╝╚══════╝
    
    📝 个人笔记管理系统 - 完全一键部署
    🚀 从零开始：克隆 + 编译 + 部署 + 启动
    🔧 自动解决所有环境问题
    🌐 支持 HTTP/HTTPS 渐进式部署
    ✨ 新服务器一条命令搞定！
EOF
    echo -e "${NC}"

    echo -e "${YELLOW}📋 此脚本将执行以下操作：${NC}"
    echo -e "   1. 检测系统环境"
    echo -e "   2. 安装基础依赖（Git、Docker、Go、Nginx等）"
    echo -e "   3. 克隆项目代码"
    echo -e "   4. 编译 Go 应用"
    echo -e "   5. 配置数据库和环境变量"
    echo -e "   6. 部署 Nginx 代理"
    echo -e "   7. 启动所有服务"
    echo -e "   8. 可选：配置 HTTPS 证书"
    echo -e "\n${GREEN}预计用时：5-15分钟${NC}"
    echo -e "\n按 Enter 继续..."
    read
}

collect_user_input() {
    log_step "收集部署配置信息"

    echo -e "${CYAN}请选择数据库类型：${NC}"
    echo -e "${YELLOW}1.${NC} 本地 Docker PostgreSQL (推荐新手)"
    echo -e "${YELLOW}2.${NC} Vercel Postgres (云数据库)"
    echo -e "${YELLOW}3.${NC} 自定义数据库"
    echo -e "\n${CYAN}请选择 (1-3):${NC}"
    read -p "> " DB_CHOICE

    case $DB_CHOICE in
    1)
        DB_TYPE="local"
        log_info "选择：本地 Docker PostgreSQL"
        ;;
    2)
        DB_TYPE="vercel"
        log_info "选择：Vercel Postgres"
        ;;
    3)
        DB_TYPE="custom"
        log_info "选择：自定义数据库"
        ;;
    *)
        log_warn "无效选择，默认使用本地数据库"
        DB_TYPE="local"
        ;;
    esac

    echo -e "${CYAN}请输入 Git 仓库地址 (默认: $DEFAULT_REPO):${NC}"
    echo -e "${YELLOW}如果是私有仓库，请确保已配置 SSH 密钥或使用 HTTPS 认证${NC}"
    read -p "> " GIT_REPO
    GIT_REPO=${GIT_REPO:-$DEFAULT_REPO}

    echo -e "\n${CYAN}请输入你的域名 (默认: $DEFAULT_DOMAIN):${NC}"
    read -p "> " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

    echo -e "\n${CYAN}请输入你的邮箱 (默认: $DEFAULT_EMAIL):${NC}"
    read -p "> " EMAIL
    EMAIL=${EMAIL:-$DEFAULT_EMAIL}

    echo -e "\n${CYAN}请设置 JWT 密钥 (留空自动生成):${NC}"
    read -p "> " JWT_SECRET
    if [[ -z "$JWT_SECRET" ]]; then
        JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        log_info "自动生成 JWT 密钥: $JWT_SECRET"
    fi
}

collect_database_config() {
    echo -e "\n${CYAN}数据库配置：${NC}"

    case $DB_TYPE in
    "local")
        echo -e "${YELLOW}数据库名称 (默认: notes_db):${NC}"
        read -p "> " DB_NAME
        DB_NAME=${DB_NAME:-notes_db}

        echo -e "${YELLOW}数据库用户名 (默认: notes_user):${NC}"
        read -p "> " DB_USER
        DB_USER=${DB_USER:-notes_user}

        echo -e "${YELLOW}数据库密码 (留空自动生成):${NC}"
        read -p "> " DB_PASSWORD
        if [[ -z "$DB_PASSWORD" ]]; then
            DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
            log_info "自动生成数据库密码: $DB_PASSWORD"
        fi
        ;;

    "vercel")
        echo -e "${YELLOW}请输入 Vercel Postgres 数据库连接字符串:${NC}"
        echo -e "${CYAN}格式: postgresql://user:password@host:5432/database?sslmode=require${NC}"
        read -p "> " VERCEL_POSTGRES_URL
        while [[ -z "$VERCEL_POSTGRES_URL" ]]; do
            log_error "数据库连接字符串不能为空"
            read -p "> " VERCEL_POSTGRES_URL
        done
        ;;

    "custom")
        echo -e "${YELLOW}数据库主机 (默认: localhost):${NC}"
        read -p "> " CUSTOM_DB_HOST
        CUSTOM_DB_HOST=${CUSTOM_DB_HOST:-localhost}

        echo -e "${YELLOW}数据库端口 (默认: 5432):${NC}"
        read -p "> " CUSTOM_DB_PORT
        CUSTOM_DB_PORT=${CUSTOM_DB_PORT:-5432}

        echo -e "${YELLOW}数据库名称:${NC}"
        read -p "> " CUSTOM_DB_NAME
        while [[ -z "$CUSTOM_DB_NAME" ]]; do
            log_error "数据库名称不能为空"
            read -p "> " CUSTOM_DB_NAME
        done

        echo -e "${YELLOW}数据库用户名:${NC}"
        read -p "> " CUSTOM_DB_USER
        while [[ -z "$CUSTOM_DB_USER" ]]; do
            log_error "数据库用户名不能为空"
            read -p "> " CUSTOM_DB_USER
        done

        echo -e "${YELLOW}数据库密码:${NC}"
        read -s -p "> " CUSTOM_DB_PASSWORD
        echo
        while [[ -z "$CUSTOM_DB_PASSWORD" ]]; do
            log_error "数据库密码不能为空"
            read -s -p "> " CUSTOM_DB_PASSWORD
            echo
        done
        ;;
    esac

    echo -e "\n${YELLOW}=== 部署配置确认 ===${NC}"
    echo -e "Git 仓库: ${GREEN}$GIT_REPO${NC}"
    echo -e "域名: ${GREEN}$DOMAIN${NC}"
    echo -e "邮箱: ${GREEN}$EMAIL${NC}"
    echo -e "应用端口: ${GREEN}$APP_PORT${NC}"
    echo -e "项目目录: ${GREEN}$PROJECT_DIR${NC}"
    echo -e "JWT 密钥: ${GREEN}$JWT_SECRET${NC}"

    case $DB_TYPE in
    "local")
        echo -e "数据库类型: ${GREEN}本地 Docker PostgreSQL${NC}"
        echo -e "数据库名: ${GREEN}$DB_NAME${NC}"
        echo -e "数据库用户: ${GREEN}$DB_USER${NC}"
        ;;
    "vercel")
        echo -e "数据库类型: ${GREEN}Vercel Postgres${NC}"
        echo -e "数据库URL: ${GREEN}${VERCEL_POSTGRES_URL:0:50}...${NC}"
        ;;
    "custom")
        echo -e "数据库类型: ${GREEN}自定义数据库${NC}"
        echo -e "数据库地址: ${GREEN}$CUSTOM_DB_HOST:$CUSTOM_DB_PORT${NC}"
        echo -e "数据库名: ${GREEN}$CUSTOM_DB_NAME${NC}"
        ;;
    esac
    
    echo -e "\n${CYAN}确认开始部署？ (y/N):${NC}"
    read -p "> " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_warn "部署已取消"
        exit 0
    fi
}

optimize_network() {
    log_step "优化网络环境"
    
    log_info "配置 DNS 服务器..."
    cp /etc/resolv.conf /etc/resolv.conf.backup || true
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 114.114.114.114
nameserver 223.5.5.5
EOF
    
    log_info "测试网络连接..."
    if ping -c 3 -W 5 8.8.8.8 &>/dev/null; then
        log_success "网络连接正常"
    else
        log_warn "网络连接可能存在问题"
    fi
    
    if curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null | grep -q "CN"; then
        log_info "检测到国内服务器，配置国内源..."
        
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            cp /etc/apt/sources.list /etc/apt/sources.list.backup || true
            
            if grep -q "debian" /etc/os-release; then
                DEBIAN_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
                cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security/ $DEBIAN_VERSION-security main contrib non-free
EOF
            elif grep -q "ubuntu" /etc/os-release; then
                UBUNTU_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
                cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse
EOF
            fi
            
            log_info "更新软件包列表..."
            apt update || {
                log_warn "国内源更新失败，恢复原始源"
                mv /etc/apt/sources.list.backup /etc/apt/sources.list 2>/dev/null || true
                apt update
            }
            
        elif [ "$PACKAGE_MANAGER" = "yum" ]; then
            yum install -y wget || true
            mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup 2>/dev/null || true
            wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo 2>/dev/null || true
            yum clean all && yum makecache || true
        fi
    fi
    
    log_success "网络环境优化完成"
}

detect_system() {
    log_step "检测系统信息"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        log_info "检测到系统: $OS_NAME $OS_VERSION"

        case "$OS_ID" in
        "centos" | "rhel" | "rocky" | "almalinux" | "opencloudos")
            PACKAGE_MANAGER="yum"
            log_info "使用 RHEL 系列部署流程"
            ;;
        "ubuntu" | "debian")
            PACKAGE_MANAGER="apt"
            log_info "使用 Debian 系列部署流程"
            ;;
        *)
            if command -v yum &>/dev/null; then
                PACKAGE_MANAGER="yum"
                log_info "检测到 yum，使用 RHEL 兼容模式"
            elif command -v apt &>/dev/null; then
                PACKAGE_MANAGER="apt"
                log_info "检测到 apt，使用 Debian 兼容模式"
            else
                log_error "不支持的系统，请手动安装"
                exit 1
            fi
            ;;
        esac
    else
        log_error "无法检测系统信息"
        exit 1
    fi

    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_success "网络连接正常"
    else
        log_error "网络连接失败，请检查网络设置"
        exit 1
    fi

    ARCH=$(uname -m)
    case $ARCH in
    x86_64)
        log_info "检测到 x86_64 架构"
        GO_ARCH="amd64"
        ;;
    aarch64 | arm64)
        log_info "检测到 ARM64 架构"
        GO_ARCH="arm64"
        ;;
    *)
        log_error "不支持的架构: $ARCH"
        exit 1
        ;;
    esac
}

install_basic_tools() {
    log_step "安装基础工具"

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        log_info "更新系统包..."
        $PACKAGE_MANAGER update -y

        log_info "安装基础工具..."
        $PACKAGE_MANAGER install -y \
            wget curl git vim nano unzip \
            firewalld device-mapper-persistent-data lvm2 \
            openssl ca-certificates \
            net-tools htop tree || {
            log_warn "部分包安装失败，继续..."
        }

        $PACKAGE_MANAGER groupinstall -y "Development Tools" || {
            log_warn "开发工具组安装失败，继续..."
        }

        $PACKAGE_MANAGER install -y epel-release || {
            log_warn "EPEL 仓库安装失败，继续..."
        }

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        log_info "更新包列表..."
        apt update

        log_info "安装基础工具..."
        apt install -y \
            wget curl git vim nano unzip \
            ufw apt-transport-https ca-certificates gnupg lsb-release \
            openssl build-essential \
            net-tools htop tree || {
            log_warn "部分包安装失败，继续..."
        }
    fi

    log_success "基础工具安装完成"
}

install_go() {
    log_step "安装 Go 语言环境"

    if command -v go &>/dev/null; then
        GO_VERSION=$(go version | cut -d' ' -f3)
        log_info "Go 已安装: $GO_VERSION"

        GO_VERSION_NUM=$(echo $GO_VERSION | sed 's/go//' | cut -d'.' -f1,2)
        if [[ $(echo "$GO_VERSION_NUM >= 1.20" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
            log_success "Go 版本满足要求"
            export PATH=$PATH:/usr/local/go/bin
            return
        else
            log_warn "Go 版本过低，重新安装..."
        fi
    fi

    log_info "下载并安装 Go 1.23..."

    cd /tmp
    rm -rf /usr/local/go

    GO_URL="https://go.dev/dl/go1.23.0.linux-${GO_ARCH}.tar.gz"
    log_info "下载地址: $GO_URL"

    wget -q --show-progress $GO_URL || {
        log_error "Go 下载失败，请检查网络连接"
        exit 1
    }

    log_info "安装 Go..."
    tar -C /usr/local -xzf go1.23.0.linux-${GO_ARCH}.tar.gz

    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >>/etc/profile
        echo 'export GOPROXY=https://goproxy.cn,direct' >>/etc/profile
        echo 'export GO111MODULE=on' >>/etc/profile
    fi

    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on

    if go version; then
        log_success "Go 安装成功: $(go version)"
    else
        log_error "Go 安装失败"
        exit 1
    fi
}

install_docker() {
    log_step "安装 Docker"

    if command -v docker &>/dev/null; then
        log_info "Docker 已安装: $(docker --version)"
        systemctl start docker || true
        systemctl enable docker || true
        return
    fi

    log_info "安装 Docker..."

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true

        $PACKAGE_MANAGER install -y yum-utils || $PACKAGE_MANAGER install -y dnf-utils || true

        if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || {
                log_warn "官方仓库添加失败，使用系统仓库"
                $PACKAGE_MANAGER install -y docker
                systemctl start docker
                systemctl enable docker
                return
            }
        fi

        $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
            log_warn "从官方仓库安装失败，尝试系统仓库..."
            $PACKAGE_MANAGER install -y docker
        }

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        
        apt remove -y docker docker-engine docker.io containerd runc || true

        apt update

        apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

        log_info "添加 Docker GPG 密钥..."
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || {
            log_warn "GPG 密钥添加失败，尝试备用方法..."
            
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8 2>/dev/null || {
                
                log_warn "官方密钥获取失败，使用系统仓库..."
                apt install -y docker.io docker-compose
                systemctl start docker
                systemctl enable docker
                
                if docker --version; then
                    log_success "Docker 安装成功: $(docker --version)"
                    return
                fi
            }
        }

        if [ -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
            if grep -q "debian" /etc/os-release; then
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            else
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            fi

            apt update

            apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
                log_warn "官方仓库安装失败，尝试系统仓库..."
                apt install -y docker.io docker-compose
            }
        else
            log_warn "使用系统仓库安装 Docker..."
            apt install -y docker.io docker-compose
        fi
    fi

    systemctl start docker
    systemctl enable docker

    if docker --version; then
        log_success "Docker 安装成功: $(docker --version)"
        
        if docker compose version &>/dev/null; then
            log_success "Docker Compose 安装成功: $(docker compose version)"
        elif command -v docker-compose &>/dev/null; then
            log_success "Docker Compose 安装成功: $(docker-compose --version)"
        else
            log_warn "Docker Compose 未安装，尝试安装..."
            
            DOCKER_COMPOSE_VERSION="v2.21.0"
            curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || {
                log_warn "Docker Compose 下载失败，使用包管理器安装..."
                if [ "$PACKAGE_MANAGER" = "apt" ]; then
                    apt install -y docker-compose-plugin || apt install -y docker-compose || true
                elif [ "$PACKAGE_MANAGER" = "yum" ]; then
                    $PACKAGE_MANAGER install -y docker-compose || true
                fi
            }
            
            if [ -f /usr/local/bin/docker-compose ]; then
                chmod +x /usr/local/bin/docker-compose
            fi
        fi
        
        if docker run --rm hello-world &>/dev/null; then
            log_success "Docker 测试通过"
        else
            log_warn "Docker 测试失败，但安装完成"
        fi
        
    else
        log_error "Docker 安装失败"
        
        echo -e "\n${YELLOW}Docker 安装故障排除：${NC}"
        echo -e "1. 检查网络连接：ping -c 3 8.8.8.8"
        echo -e "2. 检查系统版本：cat /etc/os-release"
        echo -e "3. 手动安装：apt install docker.io (Debian/Ubuntu)"
        echo -e "4. 重新运行脚本：bash $0"
        
        exit 1
    fi
}

install_certbot() {
    log_step "安装 Certbot"

    if command -v certbot &>/dev/null; then
        log_info "Certbot 已安装: $(certbot --version)"
        return
    fi

    log_info "安装 Certbot..."

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER install -y python3 python3-pip || {
            log_warn "Python3 安装失败"
        }

        pip3 install --upgrade pip || true
        pip3 install certbot || {
            log_warn "Certbot 安装失败，继续..."
        }

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        apt install -y certbot python3-certbot-nginx || {
            log_warn "Certbot 安装失败，继续..."
        }
    fi

    if command -v certbot &>/dev/null; then
        log_success "Certbot 安装成功: $(certbot --version)"
    else
        log_warn "Certbot 安装失败，将跳过 SSL 证书配置"
    fi
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

        firewall-cmd --permanent --add-service=ssh || true
        firewall-cmd --permanent --add-service=http || true
        firewall-cmd --permanent --add-service=https || true

        firewall-cmd --reload || true

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        ufw --force enable || true
        ufw allow 22/tcp || true
        ufw allow 80/tcp || true
        ufw allow 443/tcp || true
        ufw allow $APP_PORT/tcp || true
    fi

    log_success "防火墙配置完成"

    echo -e "\n${YELLOW}🔥 重要提醒：云服务器安全组配置${NC}"
    echo -e "${CYAN}请确保在云服务商控制台配置以下安全组规则：${NC}"
    echo -e "   • ${GREEN}TCP:22${NC}   (SSH 管理)"
    echo -e "   • ${GREEN}TCP:80${NC}   (HTTP 访问)"
    echo -e "   • ${GREEN}TCP:443${NC}  (HTTPS 访问)"
    echo -e "   • ${GREEN}TCP:$APP_PORT${NC}  (应用端口，可选)"
    echo -e "${YELLOW}来源地址设置为：0.0.0.0/0${NC}"
    echo -e "\n按 Enter 继续..."
    read
}

clone_project() {
    log_step "克隆项目代码"

    if [ -d "$PROJECT_DIR" ]; then
        log_info "备份现有项目目录..."
        mv $PROJECT_DIR $PROJECT_DIR.backup.$(date +%Y%m%d_%H%M%S)
    fi

    mkdir -p $PROJECT_DIR
    cd $PROJECT_DIR

    log_info "从 $GIT_REPO 克隆项目..."

    if git clone $GIT_REPO .; then
        log_success "项目克隆成功"
    else
        log_error "项目克隆失败"
        echo -e "\n${YELLOW}可能的原因和解决方案：${NC}"
        echo -e "1. ${CYAN}仓库地址错误${NC} - 请检查 Git 仓库 URL"
        echo -e "2. ${CYAN}私有仓库权限${NC} - 请配置 SSH 密钥或使用 Personal Access Token"
        echo -e "3. ${CYAN}网络问题${NC} - 请检查网络连接"
        echo -e "\n${CYAN}SSH 密钥配置方法：${NC}"
        echo -e "   ssh-keygen -t rsa -b 4096 -C \"your_email@example.com\""
        echo -e "   cat ~/.ssh/id_rsa.pub  # 复制公钥到 GitHub/GitLab"
        echo -e "\n${CYAN}HTTPS 认证方法：${NC}"
        echo -e "   git clone https://username:token@github.com/user/repo.git"
        exit 1
    fi

    log_info "检查项目结构..."
    REQUIRED_FILES=("go.mod" "cmd/server/main.go")
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "缺少必要文件: $file"
            echo -e "${YELLOW}请确保这是一个正确的 Go 项目，包含：${NC}"
            echo -e "   • go.mod (Go 模块文件)"
            echo -e "   • cmd/server/main.go (主程序入口)"
            exit 1
        fi
    done

    mkdir -p {uploads,logs,nginx,backup,scripts}
    chmod -R 755 uploads logs backup

    log_success "项目结构创建完成"
}

compile_application() {
    log_step "编译 Go 应用"

    cd $PROJECT_DIR

    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on
    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=$GO_ARCH

    log_info "检查 Go 模块..."
    if [ ! -f "go.mod" ]; then
        log_error "未找到 go.mod 文件"
        exit 1
    fi

    log_info "Go 版本: $(go version)"
    log_info "项目模块: $(head -1 go.mod)"

    log_info "下载 Go 依赖..."
    go mod download || {
        log_error "依赖下载失败"
        echo -e "${YELLOW}可能的解决方案：${NC}"
        echo -e "   • 检查网络连接"
        echo -e "   • 检查 go.mod 文件格式"
        echo -e "   • 尝试：go mod tidy"
        exit 1
    }

    log_info "整理依赖关系..."
    go mod tidy

    log_info "编译应用程序..."

    if go build -ldflags="-w -s" -trimpath -o notes-backend cmd/server/main.go; then
        chmod +x notes-backend
        log_success "应用编译成功"
        log_info "二进制文件大小: $(du -h notes-backend | cut -f1)"
    else
        log_error "应用编译失败"
        echo -e "${YELLOW}编译错误排查：${NC}"
        echo -e "   • 检查 Go 语法错误"
        echo -e "   • 检查依赖是否完整"
        echo -e "   • 检查入口文件路径"
        exit 1
    fi

    if ./notes-backend --help &>/dev/null || ./notes-backend -h &>/dev/null || true; then
        log_success "二进制文件验证通过"
    else
        log_info "二进制文件基本检查完成"
    fi
}

setup_local_database() {
    log_step "配置本地 PostgreSQL 数据库"

    cd $PROJECT_DIR

    log_info "配置 Docker 镜像加速器..."
    mkdir -p /etc/docker
    
    if [ ! -f /etc/docker/daemon.json ]; then
        cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://ccr.ccs.tencentyun.com"
  ],
  "dns": ["8.8.8.8", "8.8.4.4"],
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "storage-driver": "overlay2"
}
EOF
        
        log_info "重启 Docker 服务以应用镜像加速器..."
        systemctl daemon-reload
        systemctl restart docker
        sleep 5
        
        log_success "Docker 镜像加速器配置完成"
    else
        log_info "Docker 镜像加速器已配置"
    fi

    log_info "创建数据库 Docker Compose 配置..."
    cat >docker-compose.db.yml <<EOF
services:
  postgres:
    image: postgres:15-alpine
    container_name: notes-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: $DB_NAME
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASSWORD
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init:/docker-entrypoint-initdb.d
    networks:
      - notes-network
    command: >
      postgres -c max_connections=200
               -c shared_buffers=256MB
               -c effective_cache_size=1GB
               -c maintenance_work_mem=64MB
               -c checkpoint_completion_target=0.9
               -c wal_buffers=16MB
               -c default_statistics_target=100
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $DB_USER -d $DB_NAME"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
    driver: local

networks:
  notes-network:
    driver: bridge
EOF

    log_info "预拉取 PostgreSQL 镜像..."
    if ! docker pull postgres:15-alpine; then
        log_warn "官方镜像拉取失败，尝试国内镜像..."
        
        docker pull registry.cn-hangzhou.aliyuncs.com/library/postgres:15-alpine && \
        docker tag registry.cn-hangzhou.aliyuncs.com/library/postgres:15-alpine postgres:15-alpine || {
            log_error "无法拉取 PostgreSQL 镜像，请检查网络连接"
            
            echo -e "\n${YELLOW}故障排除建议：${NC}"
            echo -e "1. 检查网络连接：ping -c 3 8.8.8.8"
            echo -e "2. 检查 Docker 状态：systemctl status docker"
            echo -e "3. 手动拉取镜像：docker pull postgres:15-alpine"
            echo -e "4. 查看 Docker 日志：journalctl -u docker -n 50"
            
            exit 1
        }
    fi

    log_info "启动 PostgreSQL 数据库..."
    
    docker compose -f docker-compose.db.yml down 2>/dev/null || true
    docker rm -f notes-postgres 2>/dev/null || true
    
    if docker compose -f docker-compose.db.yml up -d; then
        log_success "数据库容器启动成功"
    else
        log_error "数据库容器启动失败"
        
        echo -e "\n${YELLOW}查看详细错误：${NC}"
        echo -e "docker compose -f docker-compose.db.yml logs"
        echo -e "docker logs notes-postgres"
        
        exit 1
    fi

    log_info "等待数据库启动..."
    
    for i in {1..60}; do
        if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
            log_success "数据库启动成功"
            break
        else
            if [ $i -eq 60 ]; then
                log_error "数据库启动超时"
                
                echo -e "\n${YELLOW}数据库启动故障排除：${NC}"
                echo -e "1. 查看容器状态：docker ps -a"
                echo -e "2. 查看容器日志：docker logs notes-postgres"
                echo -e "3. 检查端口占用：netstat -tlnp | grep 5432"
                echo -e "4. 重新启动：docker compose -f docker-compose.db.yml restart"
                
                echo -e "\n${CYAN}容器状态：${NC}"
                docker ps -a | grep postgres || echo "未找到 PostgreSQL 容器"
                
                echo -e "\n${CYAN}容器日志：${NC}"
                docker logs notes-postgres 2>/dev/null || echo "无法获取容器日志"
                
                exit 1
            else
                log_info "等待数据库启动... ($i/60)"
                sleep 3
            fi
        fi
    done

    log_info "验证数据库连接..."
    if docker exec notes-postgres psql -U $DB_USER -d $DB_NAME -c "SELECT version();" &>/dev/null; then
        log_success "数据库连接验证成功"
        
        DB_VERSION=$(docker exec notes-postgres psql -U $DB_USER -d $DB_NAME -t -c "SELECT version();" 2>/dev/null | head -1 | xargs)
        log_info "数据库版本: $DB_VERSION"
        
    else
        log_warn "数据库连接验证失败，但容器正在运行"
    fi

    log_success "本地数据库配置完成"
    
    echo -e "\n${CYAN}数据库连接信息：${NC}"
    echo -e "  主机: localhost"
    echo -e "  端口: 5432"
    echo -e "  数据库: $DB_NAME"
    echo -e "  用户名: $DB_USER"
    echo -e "  密码: $DB_PASSWORD"
}

create_configuration() {
    log_step "创建配置文件"

    cd $PROJECT_DIR

    log_info "创建 .env 配置文件..."
    case $DB_TYPE in
    "local")
        cat >.env <<EOF
DB_MODE=local
LOCAL_DB_HOST=localhost
LOCAL_DB_PORT=5432
LOCAL_DB_USER=$DB_USER
LOCAL_DB_PASSWORD=$DB_PASSWORD
LOCAL_DB_NAME=$DB_NAME

JWT_SECRET="$JWT_SECRET"
SERVER_PORT=$APP_PORT
GIN_MODE=release
FRONTEND_BASE_URL=https://$DOMAIN

UPLOAD_PATH=/opt/notes-backend/uploads
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000

LOG_LEVEL=info
LOG_FILE=/opt/notes-backend/logs/app.log

CORS_ORIGINS=https://$DOMAIN,http://$DOMAIN
RATE_LIMIT=100
SESSION_TIMEOUT=7200
EOF
        ;;

    "vercel")
        cat >.env <<EOF
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

LOG_LEVEL=info
LOG_FILE=/opt/notes-backend/logs/app.log

CORS_ORIGINS=https://$DOMAIN,http://$DOMAIN
RATE_LIMIT=100
SESSION_TIMEOUT=7200
EOF
        ;;

    "custom")
        cat >.env <<EOF
DB_MODE=custom
CUSTOM_DB_HOST=$CUSTOM_DB_HOST
CUSTOM_DB_PORT=$CUSTOM_DB_PORT
CUSTOM_DB_USER=$CUSTOM_DB_USER
CUSTOM_DB_PASSWORD=$CUSTOM_DB_PASSWORD
CUSTOM_DB_NAME=$CUSTOM_DB_NAME

JWT_SECRET="$JWT_SECRET"
SERVER_PORT=$APP_PORT
GIN_MODE=release
FRONTEND_BASE_URL=https://$DOMAIN

UPLOAD_PATH=/opt/notes-backend/uploads
MAX_IMAGE_SIZE=10485760
MAX_DOCUMENT_SIZE=52428800
MAX_USER_STORAGE=524288000

LOG_LEVEL=info
LOG_FILE=/opt/notes-backend/logs/app.log

CORS_ORIGINS=https://$DOMAIN,http://$DOMAIN
RATE_LIMIT=100
SESSION_TIMEOUT=7200
EOF
        ;;
    esac

    chmod 600 .env
    log_success ".env 文件创建完成"

    log_info "创建 Nginx HTTP 配置..."
    mkdir -p nginx
    cat >nginx/nginx-http.conf <<EOF
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
    error_log /var/log/nginx/error.log warn;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    server {
        listen 80;
        server_name $DOMAIN;
        
        location /health {
            proxy_pass http://172.17.0.1:$APP_PORT/health;
            access_log off;
        }
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            try_files \$uri =404;
        }
        
        location / {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_http_version 1.1;
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_cache_bypass \$http_upgrade;
            
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt)$ {
            proxy_pass http://172.17.0.1:$APP_PORT;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF

    log_info "创建 Nginx HTTPS 配置..."
    cat >nginx/nginx-https.conf <<EOF
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
    error_log /var/log/nginx/error.log warn;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 100M;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
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
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        ssl_session_tickets off;
        
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        
        location / {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_http_version 1.1;
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host \$host;
            
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
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

    log_success "Nginx 配置文件创建完成"
}

setup_ssl_certificates() {
    log_step "配置 SSL 证书目录"

    mkdir -p /var/www/certbot
    mkdir -p /etc/letsencrypt/live/$DOMAIN

    log_info "创建临时自签名证书..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
        -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
        -subj "/C=CN/ST=State/L=City/O=Organization/OU=IT/CN=$DOMAIN" &>/dev/null

    chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    chmod 600 /etc/letsencrypt/live/$DOMAIN/privkey.pem

    log_success "SSL 证书目录配置完成"
}

setup_database() {
    if [ "$DB_TYPE" = "local" ]; then
        setup_local_database
    else
        log_info "跳过本地数据库设置，使用外部数据库"
    fi
}

create_system_services() {
    log_step "创建系统服务"

    log_info "创建 notes-backend 系统服务..."
    cat >/etc/systemd/system/notes-backend.service <<EOF
[Unit]
Description=Notes Backend Application
Documentation=https://github.com/your-repo/notes-backend
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/notes-backend
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
KillSignal=SIGTERM
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$PROJECT_DIR

LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

    log_info "创建 notes-nginx-http 系统服务..."
    cat >/etc/systemd/system/notes-nginx-http.service <<EOF
[Unit]
Description=Notes Backend Nginx Proxy (HTTP)
Documentation=https://nginx.org/en/docs/
After=docker.service notes-backend.service
Requires=docker.service
Wants=notes-backend.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$PROJECT_DIR
TimeoutStartSec=300
TimeoutStopSec=60

ExecStartPre=-/usr/bin/docker stop notes-nginx
ExecStartPre=-/usr/bin/docker rm notes-nginx
ExecStartPre=/usr/bin/docker pull nginx:alpine

ExecStart=/usr/bin/docker run -d \\
    --name notes-nginx \\
    --restart unless-stopped \\
    -p 80:80 \\
    -v $PROJECT_DIR/nginx/nginx-http.conf:/etc/nginx/nginx.conf:ro \\
    -v $PROJECT_DIR/logs:/var/log/nginx \\
    -v /var/www/certbot:/var/www/certbot:ro \\
    nginx:alpine

ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=-/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF

    log_info "创建 notes-nginx-https 系统服务..."
    cat >/etc/systemd/system/notes-nginx-https.service <<EOF
[Unit]
Description=Notes Backend Nginx Proxy (HTTPS)
Documentation=https://nginx.org/en/docs/
After=docker.service notes-backend.service
Requires=docker.service
Wants=notes-backend.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$PROJECT_DIR
TimeoutStartSec=300
TimeoutStopSec=60

ExecStartPre=-/usr/bin/docker stop notes-nginx
ExecStartPre=-/usr/bin/docker rm notes-nginx
ExecStartPre=/usr/bin/docker pull nginx:alpine

ExecStart=/usr/bin/docker run -d \\
    --name notes-nginx \\
    --restart unless-stopped \\
    -p 80:80 -p 443:443 \\
    -v $PROJECT_DIR/nginx/nginx-https.conf:/etc/nginx/nginx.conf:ro \\
    -v /etc/letsencrypt:/etc/letsencrypt:ro \\
    -v $PROJECT_DIR/logs:/var/log/nginx \\
    -v /var/www/certbot:/var/www/certbot:ro \\
    nginx:alpine

ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=-/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable notes-backend

    log_success "系统服务创建完成"
}

handle_conflicts() {
    log_step "处理端口冲突和环境问题"

    log_info "停止可能冲突的服务..."
    systemctl stop nginx 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    systemctl disable httpd 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true

    log_info "清理残留进程..."
    pkill -f nginx || true
    pkill -f httpd || true
    pkill -f apache || true

    log_info "重启 Docker 服务..."
    systemctl restart docker
    sleep 5

    log_info "检查端口占用情况..."
    if netstat -tlnp | grep -q ":80 "; then
        log_warn "端口 80 仍被占用："
        netstat -tlnp | grep ":80 "
        log_info "尝试解决端口冲突..."

        PORT_80_PID=$(netstat -tlnp | grep ":80 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        if [ -n "$PORT_80_PID" ] && [ "$PORT_80_PID" != "-" ]; then
            log_info "终止占用端口 80 的进程: $PORT_80_PID"
            kill -9 $PORT_80_PID 2>/dev/null || true
            sleep 2
        fi
    fi

    if netstat -tlnp | grep -q ":80 "; then
        log_error "无法解决端口 80 冲突，请手动检查"
        exit 1
    fi

    log_success "环境冲突处理完成"
}

start_services() {
    log_step "启动应用服务"

    log_info "启动 Notes Backend 应用..."
    systemctl start notes-backend

    log_info "等待应用启动..."
    sleep 10

    if systemctl is-active --quiet notes-backend; then
        log_success "Notes Backend 应用启动成功"

        if netstat -tlnp | grep -q ":$APP_PORT "; then
            log_success "应用端口 $APP_PORT 监听正常"
        else
            log_warn "应用端口 $APP_PORT 未监听"
        fi

        log_info "测试应用健康状态..."
        for i in {1..5}; do
            if curl -f http://127.0.0.1:$APP_PORT/health &>/dev/null; then
                log_success "应用健康检查通过"
                break
            else
                log_info "等待应用就绪... ($i/5)"
                sleep 3
            fi
        done

    else
        log_error "Notes Backend 应用启动失败"
        echo -e "\n${YELLOW}查看错误日志：${NC}"
        echo -e "systemctl status notes-backend"
        echo -e "journalctl -u notes-backend -f"
        exit 1
    fi

    log_info "启动 HTTP 代理服务..."
    systemctl start notes-nginx-http

    sleep 5

    if systemctl is-active --quiet notes-nginx-http; then
        log_success "HTTP 代理启动成功"

        log_info "测试代理访问..."
        if curl -f http://127.0.0.1/health &>/dev/null; then
            log_success "HTTP 代理访问正常"
        else
            log_warn "HTTP 代理访问测试失败"
        fi

    else
        log_error "HTTP 代理启动失败"
        echo -e "\n${YELLOW}查看错误日志：${NC}"
        echo -e "systemctl status notes-nginx-http"
        echo -e "docker logs notes-nginx"
        exit 1
    fi

    log_success "所有服务启动完成"
}

setup_https_option() {
    log_step "配置 HTTPS 选项"

    if ! command -v certbot &>/dev/null; then
        log_warn "Certbot 未安装，跳过 HTTPS 配置"
        return
    fi

    log_info "检查域名解析..."
    if nslookup $DOMAIN 8.8.8.8 | grep -q "Address"; then
        log_success "域名解析正常"

        echo -e "\n${CYAN}是否现在配置 HTTPS？ (y/N):${NC}"
        echo -e "${YELLOW}注意：需要确保域名已正确解析到此服务器${NC}"
        read -p "> " SETUP_HTTPS

        if [[ "$SETUP_HTTPS" =~ ^[Yy]$ ]]; then
            setup_real_ssl_certificate
        else
            log_info "跳过 HTTPS 配置，可稍后运行 ./enable-https.sh"
        fi
    else
        log_warn "域名解析未配置或未生效"
        log_info "请先配置域名解析，稍后运行 ./enable-https.sh 启用 HTTPS"
    fi
}

setup_real_ssl_certificate() {
    log_info "获取 Let's Encrypt SSL 证书..."

    systemctl stop notes-nginx-http

    if certbot certonly --standalone \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --domains $DOMAIN \
        --non-interactive; then

        log_success "SSL 证书获取成功"

        systemctl enable notes-nginx-https
        systemctl disable notes-nginx-http
        systemctl start notes-nginx-https

        if systemctl is-active --quiet notes-nginx-https; then
            log_success "HTTPS 服务启动成功"
            setup_certificate_renewal
        else
            log_warn "HTTPS 服务启动失败，回退到 HTTP"
            systemctl start notes-nginx-http
        fi

    else
        log_warn "SSL 证书获取失败，继续使用 HTTP"
        log_info "请检查域名解析和防火墙配置"
        systemctl start notes-nginx-http
    fi
}

setup_certificate_renewal() {
    log_info "配置证书自动续期..."

    cat >/usr/local/bin/renew-ssl-certificates.sh <<EOF
echo "\$(date): 开始检查证书续期" >> /var/log/ssl-renewal.log

systemctl stop notes-nginx-https 2>/dev/null || systemctl stop notes-nginx-http 2>/dev/null

if certbot renew --quiet; then
    echo "\$(date): 证书续期成功" >> /var/log/ssl-renewal.log
    
    if systemctl is-enabled notes-nginx-https &>/dev/null; then
        systemctl start notes-nginx-https
    else
        systemctl start notes-nginx-http
    fi
    
    echo "\$(date): 服务重启完成" >> /var/log/ssl-renewal.log
else
    echo "\$(date): 证书续期失败" >> /var/log/ssl-renewal.log
    
    if systemctl is-enabled notes-nginx-https &>/dev/null; then
        systemctl start notes-nginx-https
    else
        systemctl start notes-nginx-http
    fi
fi
EOF

    chmod +x /usr/local/bin/renew-ssl-certificates.sh

    (
        crontab -l 2>/dev/null
        echo "0 3 * * * /usr/local/bin/renew-ssl-certificates.sh"
    ) | crontab -

    log_success "证书自动续期配置完成"
}

create_management_scripts() {
    log_step "创建管理脚本"

    cd $PROJECT_DIR
    mkdir -p scripts

    cat >scripts/start.sh <<EOF
echo "🚀 启动 Notes Backend 服务..."

if [ -f "docker-compose.db.yml" ]; then
    if ! docker exec notes-postgres pg_isready -U notes_user -d notes_db &>/dev/null 2>&1; then
        echo "📦 启动数据库..."
        cd /opt/notes-backend
        docker compose -f docker-compose.db.yml up -d
        echo "⏳ 等待数据库启动..."
        sleep 15
    else
        echo "✅ 数据库已在运行"
    fi
fi

systemctl start notes-backend

if systemctl is-enabled notes-nginx-https &>/dev/null && systemctl is-active notes-nginx-https &>/dev/null; then
    systemctl start notes-nginx-https
    echo "✅ 服务已启动 (HTTPS 模式)"
    echo "📱 访问地址: https://$DOMAIN"
elif systemctl is-enabled notes-nginx-http &>/dev/null; then
    systemctl start notes-nginx-http
    echo "✅ 服务已启动 (HTTP 模式)"
    echo "📱 访问地址: http://$DOMAIN"
else
    systemctl start notes-nginx-http
    echo "✅ 服务已启动 (HTTP 模式)"
    echo "📱 访问地址: http://$DOMAIN"
fi

echo "🔍 状态检查: ./scripts/status.sh"
echo "🔒 启用HTTPS: ./scripts/enable-https.sh"
EOF

    cat >scripts/stop.sh <<'EOF'
echo "🛑 停止 Notes Backend 服务..."

systemctl stop notes-nginx-https 2>/dev/null || true
systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-backend

echo "✅ 所有服务已停止"
EOF

    cat >scripts/restart.sh <<'EOF'
echo "🔄 重启 Notes Backend 服务..."

systemctl stop notes-nginx-https 2>/dev/null || true
systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-backend

sleep 3

systemctl start notes-backend
sleep 5

if systemctl is-enabled notes-nginx-https &>/dev/null; then
    systemctl start notes-nginx-https
    echo "✅ 服务已重启 (HTTPS 模式)"
else
    systemctl start notes-nginx-http
    echo "✅ 服务已重启 (HTTP 模式)"
fi
EOF

    cat >scripts/status.sh <<EOF
echo "📊 Notes Backend 服务状态"
echo "========================================"

echo -e "\n🔧 应用服务:"
systemctl status notes-backend --no-pager -l

echo -e "\n🌐 代理服务:"
if systemctl is-active --quiet notes-nginx-https; then
    echo "当前模式: HTTPS"
    systemctl status notes-nginx-https --no-pager -l
elif systemctl is-active --quiet notes-nginx-http; then
    echo "当前模式: HTTP" 
    systemctl status notes-nginx-http --no-pager -l
else
    echo "代理服务未运行"
fi

echo -e "\n📊 进程信息:"
ps aux | grep notes-backend | grep -v grep

echo -e "\n🔌 端口监听:"
netstat -tlnp | grep -E ":80|:443|:$APP_PORT"

echo -e "\n💚 健康检查:"
if systemctl is-active --quiet notes-nginx-https; then
    curl -s https://$DOMAIN/health || echo "HTTPS 健康检查失败"
elif systemctl is-active --quiet notes-nginx-http; then
    curl -s http://$DOMAIN/health || echo "HTTP 健康检查失败"
else
    curl -s http://127.0.0.1:$APP_PORT/health || echo "直连健康检查失败"
fi

echo -e "\n📈 系统资源:"
echo "CPU: \$(top -bn1 | grep "Cpu(s)" | awk '{print \$2}' | awk -F'%' '{print \$1}')%"
echo "内存: \$(free -h | awk 'NR==2{printf "%.1f%%", \$3*100/\$2 }')"
echo "磁盘: \$(df -h $PROJECT_DIR | awk 'NR==2{print \$5}')"
EOF

    cat >scripts/enable-https.sh <<EOF
echo "🔒 启用 HTTPS..."

if ! command -v certbot &> /dev/null; then
    echo "❌ Certbot 未安装，无法获取 SSL 证书"
    exit 1
fi

echo "🔍 检查域名解析..."
if ! nslookup $DOMAIN | grep -q "Address"; then
    echo "❌ 域名解析失败，请先配置域名解析"
    echo "   域名: $DOMAIN"
    echo "   应解析到: \$(curl -s ifconfig.me)"
    exit 1
fi

echo "✅ 域名解析正常"

echo "🛑 停止当前代理服务..."
systemctl stop notes-nginx-http 2>/dev/null || true
systemctl stop notes-nginx-https 2>/dev/null || true

echo "📜 获取 SSL 证书..."
if certbot certonly --standalone \\
    --email $EMAIL \\
    --agree-tos \\
    --no-eff-email \\
    --domains $DOMAIN \\
    --non-interactive; then
    
    echo "✅ SSL 证书获取成功"
    
    systemctl enable notes-nginx-https
    systemctl disable notes-nginx-http 2>/dev/null || true
    systemctl start notes-nginx-https
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo "✅ HTTPS 服务启动成功"
        echo "📱 访问地址: https://$DOMAIN"
        
        echo "🔍 测试 HTTPS 访问..."
        if curl -f https://$DOMAIN/health &>/dev/null; then
            echo "✅ HTTPS 访问测试通过"
        else
            echo "⚠️ HTTPS 访问测试失败，但服务已启动"
        fi
    else
        echo "❌ HTTPS 服务启动失败，回退到 HTTP"
        systemctl start notes-nginx-http
    fi
else
    echo "❌ SSL 证书获取失败"
    echo "请检查："
    echo "1. 域名是否正确解析到此服务器"
    echo "2. 防火墙/安全组是否开放 80、443 端口"
    echo "3. 网络连接是否正常"
    
    systemctl start notes-nginx-http
    echo "🔄 已回退到 HTTP 模式"
fi
EOF

    cat >scripts/logs.sh <<'EOF'
echo "📝 Notes Backend 日志查看"
echo "========================================"
echo "选择要查看的日志:"
echo "1. 应用日志 (实时)"
echo "2. 应用日志 (最近100行)"
echo "3. Nginx 日志 (实时)"
echo "4. Nginx 日志 (最近100行)"
echo "5. 系统日志"
echo "6. SSL 续期日志"
echo "7. 所有服务日志 (实时)"
echo ""
read -p "请选择 (1-7): " choice

case $choice in
    1)
        echo "📱 应用日志 (实时，Ctrl+C 退出):"
        journalctl -u notes-backend -f --no-pager
        ;;
    2)
        echo "📱 应用日志 (最近100行):"
        journalctl -u notes-backend -n 100 --no-pager
        ;;
    3)
        echo "🌐 Nginx 日志 (实时，Ctrl+C 退出):"
        docker logs -f notes-nginx 2>/dev/null || echo "Nginx 容器未运行"
        ;;
    4)
        echo "🌐 Nginx 日志 (最近100行):"
        docker logs --tail 100 notes-nginx 2>/dev/null || echo "Nginx 容器未运行"
        ;;
    5)
        echo "🖥️ 系统日志 (最近50行):"
        journalctl -n 50 --no-pager
        ;;
    6)
        echo "🔒 SSL 续期日志:"
        if [ -f /var/log/ssl-renewal.log ]; then
            tail -50 /var/log/ssl-renewal.log
        else
            echo "SSL 续期日志文件不存在"
        fi
        ;;
    7)
        echo "📊 所有服务日志 (实时，Ctrl+C 退出):"
        journalctl -u notes-backend -u notes-nginx-http -u notes-nginx-https -f --no-pager
        ;;
    *)
        echo "❌ 无效选择"
        ;;
esac
EOF

    cat >scripts/update.sh <<EOF
echo "🔄 更新 Notes Backend..."

cd $PROJECT_DIR

if [ ! -d ".git" ]; then
    echo "❌ 不是 Git 仓库，无法更新"
    exit 1
fi

echo "💾 备份当前版本..."
cp notes-backend notes-backend.backup.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

echo "📥 拉取最新代码..."
git fetch origin
git pull origin main || git pull origin master

export PATH=\$PATH:/usr/local/go/bin
export GOPROXY=https://goproxy.cn,direct
export GO111MODULE=on

echo "📦 更新依赖..."
go mod download
go mod tidy

echo "🔨 重新编译..."
if go build -ldflags="-w -s" -o notes-backend cmd/server/main.go; then
    echo "✅ 编译成功"
    chmod +x notes-backend
    
    echo "🔄 重启服务..."
    ./scripts/restart.sh
    
    echo "🎉 更新完成！"
    echo "📊 查看状态: ./scripts/status.sh"
else
    echo "❌ 编译失败，恢复备份..."
    if [ -f "notes-backend.backup.*" ]; then
        mv notes-backend.backup.* notes-backend
        echo "✅ 已恢复到备份版本"
    fi
    exit 1
fi
EOF

    chmod +x scripts/*.sh

    ln -sf scripts/start.sh start.sh
    ln -sf scripts/stop.sh stop.sh
    ln -sf scripts/restart.sh restart.sh
    ln -sf scripts/status.sh status.sh
    ln -sf scripts/logs.sh logs.sh
    ln -sf scripts/enable-https.sh enable-https.sh

    log_success "管理脚本创建完成"
}

verify_deployment() {
    log_step "验证部署结果"

    log_info "检查服务状态..."

    if systemctl is-active --quiet notes-backend; then
        log_success "✅ 应用服务运行正常"
    else
        log_error "❌ 应用服务未运行"
        return 1
    fi

    if systemctl is-active --quiet notes-nginx-https; then
        log_success "✅ HTTPS 代理服务运行正常"
        CURRENT_MODE="HTTPS"
    elif systemctl is-active --quiet notes-nginx-http; then
        log_success "✅ HTTP 代理服务运行正常"
        CURRENT_MODE="HTTP"
    else
        log_error "❌ 代理服务未运行"
        return 1
    fi

    log_info "检查端口监听..."

    if netstat -tlnp | grep -q ":$APP_PORT "; then
        log_success "✅ 应用端口 $APP_PORT 监听正常"
    else
        log_warn "⚠️ 应用端口 $APP_PORT 未监听"
    fi

    if netstat -tlnp | grep -q ":80 "; then
        log_success "✅ HTTP 端口 80 监听正常"
    else
        log_warn "⚠️ HTTP 端口 80 未监听"
    fi

    if [ "$CURRENT_MODE" = "HTTPS" ] && netstat -tlnp | grep -q ":443 "; then
        log_success "✅ HTTPS 端口 443 监听正常"
    fi

    log_info "检查应用健康状态..."
    for i in {1..3}; do
        if curl -f http://127.0.0.1:$APP_PORT/health &>/dev/null; then
            log_success "✅ 应用健康检查通过"
            break
        else
            log_info "等待应用就绪... ($i/3)"
            sleep 3
        fi
    done

    log_info "检查代理访问..."
    if [ "$CURRENT_MODE" = "HTTPS" ]; then
        if curl -f -k https://127.0.0.1/health &>/dev/null; then
            log_success "✅ HTTPS 代理访问正常"
        else
            log_warn "⚠️ HTTPS 代理访问异常"
        fi
    else
        if curl -f http://127.0.0.1/health &>/dev/null; then
            log_success "✅ HTTP 代理访问正常"
        else
            log_warn "⚠️ HTTP 代理访问异常"
        fi
    fi

    log_success "部署验证完成"
}

show_final_result() {
    clear
    echo -e "${GREEN}"
    cat <<'EOF'
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

    if systemctl is-active --quiet notes-nginx-https; then
        CURRENT_MODE="HTTPS"
        ACCESS_URL="https://$DOMAIN"
        PROTOCOL_ICON="🔒"
    else
        CURRENT_MODE="HTTP"
        ACCESS_URL="http://$DOMAIN"
        PROTOCOL_ICON="🌐"
    fi

    echo -e "${CYAN}📱 访问信息:${NC}"
    echo -e "   $PROTOCOL_ICON 当前模式: ${GREEN}$CURRENT_MODE${NC}"
    echo -e "   🌍 主站地址: ${GREEN}$ACCESS_URL${NC}"
    echo -e "   💚 健康检查: ${GREEN}$ACCESS_URL/health${NC}"
    echo -e "   🚀 API 基址: ${GREEN}$ACCESS_URL/api${NC}"

    if [ "$CURRENT_MODE" = "HTTP" ]; then
        echo -e "\n${YELLOW}⚠️ 当前运行在 HTTP 模式${NC}"
        echo -e "   🔒 启用 HTTPS: ${CYAN}./enable-https.sh${NC}"
        echo -e "   📋 确保域名解析正确且安全组端口已开放"
    fi

    echo -e "\n${CYAN}🔧 快速管理命令:${NC}"
    echo -e "   🚀 启动服务: ${YELLOW}./start.sh${NC}"
    echo -e "   🛑 停止服务: ${YELLOW}./stop.sh${NC}"
    echo -e "   🔄 重启服务: ${YELLOW}./restart.sh${NC}"
    echo -e "   📊 查看状态: ${YELLOW}./status.sh${NC}"
    echo -e "   📝 查看日志: ${YELLOW}./logs.sh${NC}"
    echo -e "   🔒 启用HTTPS: ${YELLOW}./enable-https.sh${NC}"

    echo -e "\n${CYAN}🛠️ 高级管理命令:${NC}"
    echo -e "   🔄 更新应用: ${YELLOW}./scripts/update.sh${NC}"
    echo -e "   📊 实时监控: ${YELLOW}./scripts/monitor.sh${NC}"

    echo -e "\n${CYAN}🖥️ 系统服务:${NC}"
    echo -e "   📱 应用服务: ${YELLOW}systemctl {start|stop|restart|status} notes-backend${NC}"
    if [ "$CURRENT_MODE" = "HTTPS" ]; then
        echo -e "   🔒 HTTPS代理: ${YELLOW}systemctl {start|stop|restart|status} notes-nginx-https${NC}"
    else
        echo -e "   🌐 HTTP代理: ${YELLOW}systemctl {start|stop|restart|status} notes-nginx-http${NC}"
    fi
    echo -e "   🔄 开机自启: ${GREEN}已启用${NC}"

    echo -e "\n${CYAN}🔒 安全配置提醒:${NC}"
    echo -e "   请确保云服务器安全组已开放以下端口："
    echo -e "   • ${GREEN}22${NC} (SSH 管理)"
    echo -e "   • ${GREEN}80${NC} (HTTP 访问)"
    echo -e "   • ${GREEN}443${NC} (HTTPS 访问)"
    echo -e "   来源设置为: ${YELLOW}0.0.0.0/0${NC}"

    echo -e "\n${CYAN}📁 重要目录:${NC}"
    echo -e "   📂 项目目录: ${GREEN}$PROJECT_DIR${NC}"
    echo -e "   ⚙️ 配置文件: ${GREEN}$PROJECT_DIR/.env${NC}"
    echo -e "   📁 上传目录: ${GREEN}$PROJECT_DIR/uploads${NC}"
    echo -e "   📝 日志目录: ${GREEN}$PROJECT_DIR/logs${NC}"
    echo -e "   🔧 脚本目录: ${GREEN}$PROJECT_DIR/scripts${NC}"

    echo -e "\n${CYAN}🔐 安全信息:${NC}"
    echo -e "   🔑 JWT 密钥: ${YELLOW}$JWT_SECRET${NC}"

    case $DB_TYPE in
        "local")
            echo -e "   🗄️ 数据库: ${GREEN}本地 Docker PostgreSQL${NC}"
            echo -e "   📊 数据库状态: ${GREEN}容器运行中${NC}"
            if [ -n "$DB_NAME" ]; then
                echo -e "   📋 数据库名: ${GREEN}$DB_NAME${NC}"
            fi
            ;;
        "vercel")
            echo -e "   🗄️ 数据库: ${GREEN}Vercel Postgres (云数据库)${NC}"
            echo -e "   🌐 连接状态: ${GREEN}已配置${NC}"
            ;;
        "custom")
            echo -e "   🗄️ 数据库: ${GREEN}自定义数据库${NC}"
            if [ -n "$CUSTOM_DB_HOST" ] && [ -n "$CUSTOM_DB_NAME" ]; then
                echo -e "   📋 数据库地址: ${GREEN}$CUSTOM_DB_HOST:$CUSTOM_DB_PORT/$CUSTOM_DB_NAME${NC}"
            fi
            ;;
        *)
            echo -e "   🗄️ 数据库: ${GREEN}已配置${NC}"
            ;;
    esac

    if [ "$CURRENT_MODE" = "HTTPS" ]; then
        echo -e "   🔒 SSL 证书: ${GREEN}Let's Encrypt (自动续期)${NC}"
    else
        echo -e "   🔒 SSL 证书: ${YELLOW}未配置${NC}"
    fi

    echo -e "\n${CYAN}🚀 API 端点示例:${NC}"
    echo -e "   👤 用户注册: ${YELLOW}POST $ACCESS_URL/api/auth/register${NC}"
    echo -e "   🔑 用户登录: ${YELLOW}POST $ACCESS_URL/api/auth/login${NC}"
    echo -e "   📄 获取笔记: ${YELLOW}GET $ACCESS_URL/api/notes${NC}"
    echo -e "   ✍️ 创建笔记: ${YELLOW}POST $ACCESS_URL/api/notes${NC}"

    echo -e "\n${CYAN}🛠️ 故障排除:${NC}"
    echo -e "   📱 应用日志: ${YELLOW}journalctl -u notes-backend -f${NC}"
    echo -e "   🌐 代理日志: ${YELLOW}docker logs notes-nginx${NC}"
    echo -e "   🔌 端口检查: ${YELLOW}netstat -tlnp | grep -E ':80|:443|:$APP_PORT'${NC}"
    echo -e "   🌍 域名解析: ${YELLOW}nslookup $DOMAIN${NC}"
    echo -e "   🔄 重置服务: ${YELLOW}./restart.sh${NC}"

    if [ "$DB_TYPE" = "local" ]; then
        echo -e "   🗄️ 数据库状态: ${YELLOW}docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME${NC}"
        echo -e "   🗄️ 数据库日志: ${YELLOW}docker logs notes-postgres${NC}"
    fi

    echo -e "\n${CYAN}📚 下一步操作:${NC}"
    echo -e "   1. 🌍 测试访问: ${GREEN}$ACCESS_URL${NC}"
    echo -e "   2. 🔒 配置安全组（如果外网无法访问）"
    if [ "$CURRENT_MODE" = "HTTP" ]; then
        echo -e "   3. 🔐 配置域名解析后启用 HTTPS"
        echo -e "   4. 👤 注册第一个用户"
        echo -e "   5. 📝 创建第一条笔记"
    else
        echo -e "   3. 👤 注册第一个用户"
        echo -e "   4. 📝 创建第一条笔记"
        echo -e "   5. 🔄 设置定期备份"
    fi

    echo -e "\n${CYAN}💡 使用技巧:${NC}"
    echo -e "   • 使用 ${YELLOW}./scripts/monitor.sh${NC} 实时监控服务状态"
    echo -e "   • 定期执行 ${YELLOW}./scripts/backup.sh${NC} 备份数据"
    echo -e "   • 使用 ${YELLOW}./scripts/update.sh${NC} 更新到最新版本"
    echo -e "   • 查看 ${YELLOW}./logs.sh${NC} 快速排查问题"

    if [ "$DB_TYPE" = "local" ]; then
        echo -e "   • 数据库备份: ${YELLOW}docker exec notes-postgres pg_dump -U $DB_USER $DB_NAME > backup.sql${NC}"
        echo -e "   • 数据库还原: ${YELLOW}docker exec -i notes-postgres psql -U $DB_USER $DB_NAME < backup.sql${NC}"
    fi

    echo -e "\n${PURPLE}===============================================${NC}"
    echo -e "${GREEN}✨ Notes Backend 完全部署成功！${NC}"
    echo -e "${GREEN}🎉 祝您使用愉快！${NC}"
    echo -e "${PURPLE}===============================================${NC}"

    echo -e "\n${CYAN}🔍 最终连接测试:${NC}"
    if curl -f $ACCESS_URL/health &>/dev/null; then
        echo -e "   ${GREEN}✅ 外部访问测试通过${NC}"
    else
        echo -e "   ${YELLOW}⚠️ 外部访问测试失败${NC}"
        echo -e "   ${YELLOW}请检查域名解析和安全组配置${NC}"
        echo -e "   ${YELLOW}本地测试: curl http://127.0.0.1/health${NC}"
    fi

    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "获取失败")
    echo -e "   🌍 服务器 IP: ${GREEN}$PUBLIC_IP${NC}"

    if [ "$PUBLIC_IP" != "获取失败" ]; then
        echo -e "   📋 域名应解析到: ${GREEN}$PUBLIC_IP${NC}"
    fi
}

cleanup_on_error() {
    log_error "部署过程中出现错误，正在清理..."

    systemctl stop notes-backend 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl stop notes-nginx-https 2>/dev/null || true

    docker stop notes-nginx 2>/dev/null || true
    docker rm notes-nginx 2>/dev/null || true

    echo -e "\n${YELLOW}错误日志查看命令：${NC}"
    echo -e "systemctl status notes-backend"
    echo -e "journalctl -u notes-backend -n 50"
    echo -e "docker logs notes-nginx"

    echo -e "\n${YELLOW}如需帮助，请提供上述日志信息${NC}"

    exit 1
}

main() {
    trap cleanup_on_error ERR

    check_root
    show_welcome
    collect_user_input
    collect_database_config
    detect_system
    optimize_network
    install_basic_tools
    install_go
    install_docker
    install_certbot
    setup_firewall
    clone_project
    setup_database

    compile_application
    create_configuration
    setup_ssl_certificates
    create_system_services
    handle_conflicts
    start_services
    setup_https_option
    create_management_scripts
    verify_deployment
    show_final_result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
