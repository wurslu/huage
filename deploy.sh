detect_system() {
    log_step "检测系统信息和已安装组件"

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

    log_info "检测已安装的组件..."
    
    BASIC_TOOLS_INSTALLED=true
    missing_tools=()
    for tool in wget curl git; do
        if ! command -v $tool &>/dev/null; then
            BASIC_TOOLS_INSTALLED=false
            missing_tools+=($tool)
        fi
    done
    
    if [ "$BASIC_TOOLS_INSTALLED" = true ]; then
        log_success "✅ 基础工具已安装"
    else
        log_warn "⚠️ 缺少基础工具: ${missing_tools[*]}"
    fi

    GO_INSTALLED=false
    if command -v go &>/dev/null; then
        GO_VERSION=$(go version | cut -d' ' -f3)
        GO_VERSION_NUM=$(echo $GO_VERSION | sed 's/go//' | cut -d'.' -f1,2)
        if [[ $(echo "$GO_VERSION_NUM >= 1.20" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
            GO_INSTALLED=true
            log_success "✅ Go 已安装且版本满足要求: $GO_VERSION"
        else
            log_warn "⚠️ Go 版本过低: $GO_VERSION，需要 1.20+，将重新安装"
        fi
    else
        log_warn "⚠️ Go 未安装"
    fi

    DOCKER_INSTALLED=false
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        DOCKER_INSTALLED=true
        log_success "✅ Docker 已安装并运行: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        
        if docker compose version &>/dev/null; then
            log_success "✅ Docker Compose 已安装: $(docker compose version --short)"
        elif command -v docker-compose &>/dev/null; then
            log_success "✅ Docker Compose 已安装: $(docker-compose --version | cut -d' ' -f3 | tr -d ',')"
        else
            log_warn "⚠️ Docker Compose 未安装"
        fi
    else
        log_warn "⚠️ Docker 未安装或未运行"
    fi

    CERTBOT_INSTALLED=false
    if command -v certbot &>/dev/null; then
        CERTBOT_INSTALLED=true
        log_success "✅ Certbot 已安装: $(certbot --version 2>&1 | head -1)"
    else
        log_warn "⚠️ Certbot 未安装"
    fi

    PROJECT_EXISTS=false
    if [ -d "$PROJECT_DIR" ]; then
        cd $PROJECT_DIR
        if [ -f "go.mod" ] && [ -f "cmd/server/main.go" ] && [ -f "notes-backend" ]; then
            PROJECT_EXISTS=true
            log_success "✅ 项目已存在且已编译"
            
            if [ -f ".env" ]; then
                log_success "✅ 配置文件已存在"
                CONFIG_EXISTS=true
            else
                log_warn "⚠️ 配置文件不存在"
                CONFIG_EXISTS=false
            fi
        elif [ -f "go.mod" ] && [ -f "cmd/server/main.go" ]; then
            log_success "✅ 项目代码已存在，但未编译"
            PROJECT_CLONED=true
            PROJECT_COMPILED=false
        else
            log_warn "⚠️ 项目目录存在但不完整"
        fi
    else
        log_warn "⚠️ 项目不存在"
    fi

    SERVICES_RUNNING=false
    if systemctl is-active --quiet notes-backend; then
        if systemctl is-active --quiet notes-nginx-https || systemctl is-active --quiet notes-nginx-http; then
            SERVICES_RUNNING=true
            log_success "✅ 服务正在运行"
            
            if curl -f http://127.0.0.1:9191/health &>/dev/null; then
                log_success "✅ 服务健康检查通过"
                SERVICES_HEALTHY=true
            else
                log_warn "⚠️ 服务运行但健康检查失败"
                SERVICES_HEALTHY=false
            fi
        else
            log_warn "⚠️ 应用服务运行但代理服务未运行"
        fi
    else
        log_warn "⚠️ 服务未运行"
    fi

    LOCAL_DB_RUNNING=false
    if docker ps | grep -q notes-postgres; then
        if docker exec notes-postgres pg_isready &>/dev/null; then
            LOCAL_DB_RUNNING=true
            log_success "✅ 本地数据库运行正常"
        else
            log_warn "⚠️ 本地数据库容器存在但连接失败"
        fi
    fi

    FIREWALL_CONFIGURED=false
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        if systemctl is-active --quiet firewalld; then
            if firewall-cmd --list-ports | grep -q "80/tcp\|443/tcp"; then
                FIREWALL_CONFIGURED=true
                log_success "✅ 防火墙已配置"
            else
                log_warn "⚠️ 防火墙未正确配置端口"
            fi
        else
            log_warn "⚠️ firewalld 未运行"
        fi
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        if ufw status | grep -q "Status: active"; then
            if ufw status | grep -q "80\|443"; then
                FIREWALL_CONFIGURED=true
                log_success "✅ 防火墙已配置"
            else
                log_warn "⚠️ 防火墙未正确配置端口"
            fi
        else
            log_warn "⚠️ ufw 未启用"
        fi
    fi

    echo -e "\n${CYAN}=== 系统检测报告 ===${NC}"
    echo -e "操作系统: ${GREEN}$OS_NAME $OS_VERSION${NC}"
    echo -e "架构: ${GREEN}$ARCH${NC}"
    echo -e "包管理器: ${GREEN}$PACKAGE_MANAGER${NC}"
    echo -e ""
    echo -e "组件状态:"
    [ "$BASIC_TOOLS_INSTALLED" = true ] && echo -e "  基础工具: ${GREEN}✅ 已安装${NC}" || echo -e "  基础工具: ${YELLOW}⚠️ 需要安装${NC}"
    [ "$GO_INSTALLED" = true ] && echo -e "  Go语言: ${GREEN}✅ 已安装${NC}" || echo -e "  Go语言: ${YELLOW}⚠️ 需要安装${NC}"
    [ "$DOCKER_INSTALLED" = true ] && echo -e "  Docker: ${GREEN}✅ 已安装${NC}" || echo -e "  Docker: ${YELLOW}⚠️ 需要安装${NC}"
    [ "$CERTBOT_INSTALLED" = true ] && echo -e "  Certbot: ${GREEN}✅ 已安装${NC}" || echo -e "  Certbot: ${YELLOW}⚠️ 需要安装${NC}"
    [ "$PROJECT_EXISTS" = true ] && echo -e "  项目: ${GREEN}✅ 已部署${NC}" || echo -e "  项目: ${YELLOW}⚠️ 需要部署${NC}"
    [ "$SERVICES_RUNNING" = true ] && echo -e "  服务: ${GREEN}✅ 运行中${NC}" || echo -e "  服务: ${YELLOW}⚠️ 未运行${NC}"
    [ "$LOCAL_DB_RUNNING" = true ] && echo -e "  本地数据库: ${GREEN}✅ 运行中${NC}" || echo -e "  本地数据库: ${YELLOW}⚠️ 未运行${NC}"
    [ "$FIREWALL_CONFIGURED" = true ] && echo -e "  防火墙: ${GREEN}✅ 已配置${NC}" || echo -e "  防火墙: ${YELLOW}⚠️ 需要配置${NC}"

    log_success "系统检测完成"
}

install_basic_tools() {
    if [ "$BASIC_TOOLS_INSTALLED" = true ]; then
        log_success "基础工具已安装，跳过安装步骤"
        return 0
    fi

    log_step "安装基础工具"

    missing_tools=()
    for tool in wget curl git vim nano unzip openssl; do
        if ! command -v $tool &>/dev/null; then
            missing_tools+=($tool)
        fi
    done

    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "所有基础工具已安装"
        return 0
    fi

    log_info "需要安装的工具: ${missing_tools[*]}"

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        last_update=""
        if [ -f /var/cache/yum/timedhosts.txt ]; then
            last_update=$(stat -c %Y /var/cache/yum/timedhosts.txt 2>/dev/null || echo "0")
        fi
        current_time=$(date +%s)
        update_diff=$((current_time - ${last_update:-0}))
        
        if [ $update_diff -gt 86400 ]; then
            log_info "更新系统包列表..."
            $PACKAGE_MANAGER update -y
        else
            log_info "包列表较新，跳过更新"
        fi

        log_info "安装基础工具..."
        tools_to_install=""
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "vim"|"nano"|"unzip"|"wget"|"curl"|"git"|"openssl")
                    tools_to_install="$tools_to_install $tool"
                    ;;
            esac
        done

        if [ -n "$tools_to_install" ]; then
            $PACKAGE_MANAGER install -y $tools_to_install || {
                log_warn "部分工具安装失败，继续..."
            }
        fi

        if ! rpm -qa | grep -q "gcc\|make"; then
            log_info "安装开发工具组..."
            $PACKAGE_MANAGER groupinstall -y "Development Tools" || {
                log_warn "开发工具组安装失败，尝试单独安装..."
                $PACKAGE_MANAGER install -y gcc gcc-c++ make || {
                    log_warn "开发工具安装失败，继续..."
                }
            }
        else
            log_info "开发工具已安装，跳过"
        fi

        if ! rpm -qa | grep -q epel-release; then
            log_info "安装EPEL仓库..."
            $PACKAGE_MANAGER install -y epel-release || {
                log_warn "EPEL 仓库安装失败，继续..."
            }
        else
            log_info "EPEL仓库已安装，跳过"
        fi

        extra_tools=""
        for tool in firewalld device-mapper-persistent-data lvm2 ca-certificates net-tools htop tree; do
            if ! rpm -qa | grep -q $tool; then
                extra_tools="$extra_tools $tool"
            fi
        done
        
        if [ -n "$extra_tools" ]; then
            log_info "安装额外工具: $extra_tools"
            $PACKAGE_MANAGER install -y $extra_tools || {
                log_warn "部分额外工具安装失败，继续..."
            }
        fi

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        last_update="0"
        if [ -f /var/lib/apt/lists/lock ]; then
            last_update=$(stat -c %Y /var/lib/apt/lists/lock 2>/dev/null || echo "0")
        fi
        current_time=$(date +%s)
        update_diff=$((current_time - last_update))
        
        if [ $update_diff -gt 86400 ]; then
            log_info "更新包列表..."
            apt update
        else
            log_info "包列表较新，跳过更新"
        fi

        log_info "安装基础工具..."
        tools_to_install=""
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "vim"|"nano"|"unzip"|"wget"|"curl"|"git"|"openssl")
                    tools_to_install="$tools_to_install $tool"
                    ;;
            esac
        done

        if [ -n "$tools_to_install" ]; then
            apt install -y $tools_to_install || {
                log_warn "部分工具安装失败，继续..."
            }
        fi

        if ! dpkg -l | grep -q "build-essential"; then
            log_info "安装开发工具..."
            apt install -y build-essential || {
                log_warn "开发工具安装失败，继续..."
            }
        else
            log_info "开发工具已安装，跳过"
        fi

        extra_tools=""
        for tool in ufw apt-transport-https ca-certificates gnupg lsb-release net-tools htop tree; do
            if ! dpkg -l | grep -q "^ii.*$tool"; then
                extra_tools="$extra_tools $tool"
            fi
        done
        
        if [ -n "$extra_tools" ]; then
            log_info "安装额外工具: $extra_tools"
            apt install -y $extra_tools || {
                log_warn "部分额外工具安装失败，继续..."
            }
        fi
    fi

    log_info "验证工具安装..."
    failed_tools=()
    for tool in wget curl git; do
        if ! command -v $tool &>/dev/null; then
            failed_tools+=($tool)
        fi
    done

    if [ ${#failed_tools[@]} -eq 0 ]; then
        log_success "基础工具安装完成"
        BASIC_TOOLS_INSTALLED=true
    else
        log_error "以下关键工具安装失败: ${failed_tools[*]}"
        log_error "请手动安装这些工具后重新运行脚本"
        exit 1
    fi

    log_info "已安装工具版本:"
    for tool in wget curl git; do
        if command -v $tool &>/dev/null; then
            version=$($tool --version 2>/dev/null | head -1 | cut -d' ' -f1-3 || echo "版本信息获取失败")
            log_info "  $tool: $version"
        fi
    done
}

install_go() {
    if [ "$GO_INSTALLED" = true ]; then
        log_success "Go 语言已安装且版本满足要求，跳过安装步骤"
        export PATH=$PATH:/usr/local/go/bin
        export GOPROXY=https://goproxy.cn,direct
        export GO111MODULE=on
        log_info "当前 Go 版本: $(go version)"
        return 0
    fi

    log_step "安装 Go 语言环境"

    if command -v go &>/dev/null; then
        current_version=$(go version | cut -d' ' -f3)
        log_warn "检测到较旧的 Go 版本: $current_version，将升级到 Go 1.23"
        
        if grep -q "go/bin" ~/.bashrc 2>/dev/null; then
            log_info "备份用户级Go环境配置..."
            cp ~/.bashrc ~/.bashrc.go.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        fi
    else
        log_info "开始安装 Go 1.23..."
    fi

    target_go_path="/usr/local/go"
    if [ -d "$target_go_path" ] && [ -x "$target_go_path/bin/go" ]; then
        existing_version=$($target_go_path/bin/go version 2>/dev/null | cut -d' ' -f3 || echo "unknown")
        if [[ "$existing_version" == "go1.23"* ]]; then
            log_info "检测到目标版本已存在: $existing_version"
            log_info "配置环境变量..."
            
            export PATH=$PATH:/usr/local/go/bin
            export GOPROXY=https://goproxy.cn,direct
            export GO111MODULE=on
            
            setup_go_environment
            
            log_success "Go 1.23 安装验证通过"
            GO_INSTALLED=true
            return 0
        else
            log_info "检测到不同版本: $existing_version，将替换为 Go 1.23"
        fi
    fi

    cd /tmp

    log_info "清理旧版本 Go..."
    rm -rf /usr/local/go

    GO_VERSION="1.23.0"
    GO_FILENAME="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    GO_URL="https://go.dev/dl/${GO_FILENAME}"
    
    log_info "下载 Go ${GO_VERSION} for ${GO_ARCH}..."
    log_info "下载地址: $GO_URL"

    if [ -f "$GO_FILENAME" ]; then
        log_info "检测到已下载的安装包，验证完整性..."
        
        file_size=$(stat -f%z "$GO_FILENAME" 2>/dev/null || stat -c%s "$GO_FILENAME" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 104857600 ]; then  # 100MB
            log_info "使用已下载的安装包"
        else
            log_warn "已下载文件可能不完整，重新下载..."
            rm -f "$GO_FILENAME"
        fi
    fi

    if [ ! -f "$GO_FILENAME" ]; then
        download_success=false
        
        if command -v wget &>/dev/null && [ "$download_success" = false ]; then
            log_info "使用 wget 下载..."
            if wget -q --show-progress --timeout=30 --tries=3 "$GO_URL"; then
                download_success=true
            else
                log_warn "wget 下载失败"
            fi
        fi
        
        if command -v curl &>/dev/null && [ "$download_success" = false ]; then
            log_info "使用 curl 下载..."
            if curl -L --progress-bar --connect-timeout 30 --retry 3 -o "$GO_FILENAME" "$GO_URL"; then
                download_success=true
            else
                log_warn "curl 下载失败"
                rm -f "$GO_FILENAME"
            fi
        fi
        
        if [ "$download_success" = false ]; then
            log_error "Go 下载失败，请检查网络连接"
            echo -e "\n${YELLOW}解决方案：${NC}"
            echo -e "1. 检查网络连接：ping -c 3 go.dev"
            echo -e "2. 手动下载：wget $GO_URL"
            echo -e "3. 使用国内镜像或代理"
            exit 1
        fi
    fi

    log_info "验证下载文件..."
    if [ ! -f "$GO_FILENAME" ]; then
        log_error "下载文件不存在"
        exit 1
    fi
    
    file_size=$(stat -f%z "$GO_FILENAME" 2>/dev/null || stat -c%s "$GO_FILENAME" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 104857600 ]; then  # 100MB
        log_error "下载文件大小异常，可能下载不完整"
        rm -f "$GO_FILENAME"
        exit 1
    fi

    log_info "安装 Go..."
    if tar -C /usr/local -xzf "$GO_FILENAME"; then
        log_success "Go 解压完成"
    else
        log_error "Go 解压失败"
        exit 1
    fi

    setup_go_environment

    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on

    if /usr/local/go/bin/go version; then
        installed_version=$(/usr/local/go/bin/go version | cut -d' ' -f3)
        log_success "Go 安装成功: $installed_version"
        GO_INSTALLED=true
        
        log_info "测试 Go 环境..."
        if echo 'package main; import "fmt"; func main() { fmt.Println("Go 环境测试成功") }' | /usr/local/go/bin/go run - &>/dev/null; then
            log_success "Go 环境测试通过"
        else
            log_warn "Go 环境测试失败，但安装完成"
        fi
        
        rm -f "$GO_FILENAME"
        
    else
        log_error "Go 安装失败"
        exit 1
    fi
}

setup_go_environment() {
    log_info "配置 Go 环境变量..."
    
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        log_info "添加 Go 到系统 PATH..."
        cat >> /etc/profile << 'EOF'

export PATH=$PATH:/usr/local/go/bin
export GOPROXY=https://goproxy.cn,direct
export GO111MODULE=on
EOF
        log_success "系统环境变量配置完成"
    else
        log_info "系统环境变量已配置"
    fi
    
    user_shell_config=""
    if [ -n "$HOME" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            user_shell_config="$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            user_shell_config="$HOME/.bash_profile"
        elif [ -f "$HOME/.profile" ]; then
            user_shell_config="$HOME/.profile"
        fi
        
        if [ -n "$user_shell_config" ] && ! grep -q "/usr/local/go/bin" "$user_shell_config"; then
            log_info "添加 Go 到用户环境变量..."
            cat >> "$user_shell_config" << 'EOF'

export PATH=$PATH:/usr/local/go/bin
export GOPROXY=https://goproxy.cn,direct
export GO111MODULE=on
EOF
            log_success "用户环境变量配置完成"
        fi
    fi
    
    if [ ! -L "/usr/local/bin/go" ]; then
        ln -sf /usr/local/go/bin/go /usr/local/bin/go 2>/dev/null || true
        ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt 2>/dev/null || true
        log_info "创建 Go 符号链接完成"
    fi
}

install_docker() {
    if [ "$DOCKER_INSTALLED" = true ]; then
        log_success "Docker 已安装并运行，跳过安装步骤"
        
        if ! systemctl is-enabled --quiet docker; then
            log_info "启用 Docker 自启动..."
            systemctl enable docker
        fi
        
        if ! systemctl is-active --quiet docker; then
            log_info "启动 Docker 服务..."
            systemctl start docker
            sleep 3
        fi
        
        check_docker_compose
        return 0
    fi

    log_step "安装 Docker"

    if command -v docker &>/dev/null; then
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        log_info "检测到已安装的 Docker: $docker_version"
        
        log_info "尝试启动 Docker 服务..."
        systemctl start docker
        systemctl enable docker
        sleep 5
        
        if systemctl is-active --quiet docker; then
            log_success "Docker 服务启动成功"
            DOCKER_INSTALLED=true
            check_docker_compose
            return 0
        else
            log_warn "Docker 已安装但服务启动失败，将重新安装"
        fi
    fi

    log_info "开始安装 Docker..."

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        install_docker_rhel
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        install_docker_debian
    fi

    log_info "启动 Docker 服务..."
    systemctl start docker
    systemctl enable docker
    sleep 5

    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log_success "Docker 安装成功: $docker_version"
        DOCKER_INSTALLED=true
        
        test_docker_installation
        
        check_docker_compose
        
        configure_docker_mirrors
        
    else
        log_error "Docker 安装失败"
        show_docker_troubleshooting
        exit 1
    fi
}

install_docker_rhel() {
    log_info "在 RHEL 系列系统上安装 Docker..."
    
    log_info "卸载可能存在的旧版本..."
    $PACKAGE_MANAGER remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc &>/dev/null || true

    log_info "安装必要依赖..."
    $PACKAGE_MANAGER install -y yum-utils device-mapper-persistent-data lvm2 || \
    $PACKAGE_MANAGER install -y dnf-utils device-mapper-persistent-data lvm2 || true

    if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
        log_info "添加 Docker 官方仓库..."
        if yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo; then
            log_success "Docker 仓库添加成功"
        else
            log_warn "官方仓库添加失败，尝试使用系统仓库..."
            install_docker_system_repo_rhel
            return 0
        fi
    else
        log_info "Docker 仓库已存在"
    fi

    log_info "安装 Docker CE..."
    if $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_success "Docker CE 安装成功"
    else
        log_warn "Docker CE 安装失败，尝试系统仓库..."
        install_docker_system_repo_rhel
    fi
}

install_docker_system_repo_rhel() {
    log_info "使用系统仓库安装 Docker..."
    
    if $PACKAGE_MANAGER install -y docker; then
        log_success "系统仓库 Docker 安装成功"
        
        if ! command -v docker-compose &>/dev/null; then
            log_info "安装 docker-compose..."
            $PACKAGE_MANAGER install -y docker-compose || install_docker_compose_binary
        fi
    else
        log_error "Docker 安装失败"
        exit 1
    fi
}

install_docker_debian() {
    log_info "在 Debian 系列系统上安装 Docker..."
    
    log_info "卸载可能存在的旧版本..."
    apt remove -y docker docker-engine docker.io containerd runc &>/dev/null || true

    log_info "更新包索引..."
    apt update

    log_info "安装必要依赖..."
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

    log_info "添加 Docker GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || {
        log_warn "官方GPG密钥添加失败，尝试备用方法..."
        install_docker_system_repo_debian
        return 0
    }

    if grep -q "debian" /etc/os-release; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    apt update

    log_info "安装 Docker CE..."
    if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_success "Docker CE 安装成功"
    else
        log_warn "Docker CE 安装失败，尝试系统仓库..."
        install_docker_system_repo_debian
    fi
}

install_docker_system_repo_debian() {
    log_info "使用系统仓库安装 Docker..."
    
    if apt install -y docker.io docker-compose; then
        log_success "系统仓库 Docker 安装成功"
    else
        log_error "Docker 安装失败"
        exit 1
    fi
}

check_docker_compose() {
    log_info "检查 Docker Compose..."
    
    if docker compose version &>/dev/null; then
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_success "Docker Compose (Plugin) 已安装: $compose_version"
    elif command -v docker-compose &>/dev/null; then
        compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        log_success "Docker Compose (Standalone) 已安装: $compose_version"
    else
        log_warn "Docker Compose 未安装，尝试安装..."
        install_docker_compose_binary
    fi
}

install_docker_compose_binary() {
    log_info "下载并安装 Docker Compose 二进制文件..."
    
    DOCKER_COMPOSE_VERSION="v2.21.0"
    COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    
    if curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        
        if command -v docker-compose &>/dev/null; then
            compose_version=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
            log_success "Docker Compose 二进制安装成功: $compose_version"
        else
            log_warn "Docker Compose 二进制安装失败"
        fi
    else
        log_warn "Docker Compose 下载失败"
    fi
}

test_docker_installation() {
    log_info "测试 Docker 安装..."
    
    if docker info &>/dev/null; then
        log_success "Docker daemon 运行正常"
    else
        log_warn "Docker daemon 状态异常"
        return 1
    fi
    
    log_info "测试容器运行..."
    if timeout 30 docker run --rm hello-world &>/dev/null; then
        log_success "Docker 容器测试通过"
    else
        log_warn "Docker 容器测试失败，但守护进程正常"
    fi
}

configure_docker_mirrors() {
    log_info "配置 Docker 镜像加速器..."
    
    if [ -f /etc/docker/daemon.json ]; then
        if grep -q "registry-mirrors" /etc/docker/daemon.json; then
            log_info "Docker 镜像加速器已配置"
            return 0
        fi
    fi
    
    mkdir -p /etc/docker
    
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
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  }
}
EOF
    
    log_info "重启 Docker 服务以应用镜像加速器..."
    systemctl daemon-reload
    systemctl restart docker
    sleep 5
    
    if systemctl is-active --quiet docker; then
        log_success "Docker 镜像加速器配置完成"
    else
        log_warn "Docker 重启失败，但镜像加速器已配置"
        systemctl start docker
    fi
}

show_docker_troubleshooting() {
    echo -e "\n${YELLOW}Docker 安装故障排除：${NC}"
    echo -e "1. 检查系统版本兼容性"
    echo -e "2. 检查网络连接：ping -c 3 download.docker.com"
    echo -e "3. 检查系统日志：journalctl -u docker -n 50"
    echo -e "4. 手动安装尝试："
    
    if [ "$PACKAGE_MANAGER" = "apt" ]; then
        echo -e "   apt update && apt install -y docker.io"
    elif [ "$PACKAGE_MANAGER" = "yum" ]; then
        echo -e "   yum install -y docker"
    fi
    
    echo -e "5. 重新运行脚本：bash $0"
}

install_certbot() {
    if [ "$CERTBOT_INSTALLED" = true ]; then
        log_success "Certbot 已安装，跳过安装步骤"
        certbot_version=$(certbot --version 2>&1 | head -1)
        log_info "当前版本: $certbot_version"
        
        if certbot --help &>/dev/null; then
            log_success "Certbot 功能验证通过"
        else
            log_warn "Certbot 安装但功能异常，将重新安装"
            CERTBOT_INSTALLED=false
        fi
        
        if [ "$CERTBOT_INSTALLED" = true ]; then
            return 0
        fi
    fi

    log_step "安装 Certbot"

    if command -v certbot &>/dev/null; then
        log_info "检测到现有 Certbot 安装，检查状态..."
        if ! certbot --help &>/dev/null; then
            log_warn "现有 Certbot 安装损坏，将重新安装"
            remove_broken_certbot
        fi
    fi

    log_info "开始安装 Certbot..."

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        install_certbot_rhel
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        install_certbot_debian
    fi

    verify_certbot_installation
}

install_certbot_rhel() {
    log_info "在 RHEL 系列系统上安装 Certbot..."
    
    if install_certbot_package_rhel; then
        return 0
    fi
    
    log_warn "包管理器安装失败，尝试使用 pip 安装..."
    install_certbot_pip
}

install_certbot_package_rhel() {
    log_info "使用包管理器安装 Certbot..."
    
    if ! rpm -qa | grep -q epel-release; then
        log_info "安装 EPEL 仓库..."
        $PACKAGE_MANAGER install -y epel-release || {
            log_warn "EPEL 仓库安装失败"
            return 1
        }
    fi
    
    if [[ "$OS_VERSION" == "8"* ]] || [[ "$OS_VERSION" == "9"* ]]; then
        log_info "检测到 RHEL 8/9 系列，尝试多种安装方式..."
        
        if command -v dnf &>/dev/null; then
            if dnf install -y certbot python3-certbot-nginx &>/dev/null; then
                log_success "使用 dnf 安装 Certbot 成功"
                return 0
            fi
        fi
        
        if $PACKAGE_MANAGER install -y certbot python3-certbot-nginx &>/dev/null; then
            log_success "使用 yum 安装 Certbot 成功"
            return 0
        fi
        
        if install_certbot_snap; then
            return 0
        fi
        
    else
        if $PACKAGE_MANAGER install -y certbot python2-certbot-nginx &>/dev/null || \
           $PACKAGE_MANAGER install -y certbot &>/dev/null; then
            log_success "使用传统包管理器安装 Certbot 成功"
            return 0
        fi
    fi
    
    log_warn "包管理器安装失败"
    return 1
}

install_certbot_debian() {
    log_info "在 Debian 系列系统上安装 Certbot..."
    
    if install_certbot_package_debian; then
        return 0
    fi
    
    log_warn "包管理器安装失败，尝试使用 pip 安装..."
    install_certbot_pip
}

install_certbot_package_debian() {
    log_info "使用包管理器安装 Certbot..."
    
    apt update
    
    if apt install -y certbot python3-certbot-nginx; then
        log_success "使用 apt 安装 Certbot 成功"
        return 0
    fi
    
    if apt install -y certbot; then
        log_success "使用 apt 安装基本 Certbot 成功"
        log_warn "Nginx 插件安装失败，但基本功能可用"
        return 0
    fi
    
    if install_certbot_snap; then
        return 0
    fi
    
    log_warn "包管理器安装失败"
    return 1
}

install_certbot_pip() {
    log_info "使用 pip 安装 Certbot..."
    
    install_python_deps
    
    python3 -m pip install --upgrade pip &>/dev/null || true
    
    if python3 -m pip install certbot certbot-nginx; then
        log_success "使用 pip 安装 Certbot 成功"
        
        if [ ! -L "/usr/local/bin/certbot" ] && [ -f "$HOME/.local/bin/certbot" ]; then
            ln -sf "$HOME/.local/bin/certbot" /usr/local/bin/certbot 2>/dev/null || true
        fi
        
        return 0
    else
        log_warn "pip 安装失败"
        return 1
    fi
}

install_certbot_snap() {
    log_info "尝试使用 snap 安装 Certbot..."
    
    if ! command -v snap &>/dev/null; then
        log_info "安装 snapd..."
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            apt install -y snapd || return 1
        elif [ "$PACKAGE_MANAGER" = "yum" ]; then
            $PACKAGE_MANAGER install -y snapd || return 1
            systemctl enable --now snapd.socket || return 1
        fi
        
        sleep 10
    fi
    
    if snap install core && snap refresh core && snap install --classic certbot; then
        ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
        log_success "使用 snap 安装 Certbot 成功"
        return 0
    else
        log_warn "snap 安装失败"
        return 1
    fi
}

install_python_deps() {
    log_info "检查 Python 环境..."
    
    if ! command -v python3 &>/dev/null; then
        log_info "安装 Python3..."
        if [ "$PACKAGE_MANAGER" = "yum" ]; then
            $PACKAGE_MANAGER install -y python3 python3-pip
        elif [ "$PACKAGE_MANAGER" = "apt" ]; then
            apt install -y python3 python3-pip
        fi
    fi
    
    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null; then
        log_info "安装 pip..."
        if [ "$PACKAGE_MANAGER" = "yum" ]; then
            $PACKAGE_MANAGER install -y python3-pip
        elif [ "$PACKAGE_MANAGER" = "apt" ]; then
            apt install -y python3-pip
        fi
    fi
}

remove_broken_certbot() {
    log_info "移除损坏的 Certbot 安装..."
    
    systemctl stop certbot* 2>/dev/null || true
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER remove -y certbot python*certbot* &>/dev/null || true
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        apt remove -y certbot python*certbot* &>/dev/null || true
        apt autoremove -y &>/dev/null || true
    fi
    
    python3 -m pip uninstall -y certbot certbot-nginx &>/dev/null || true
    
    snap remove certbot &>/dev/null || true
    
    rm -f /usr/local/bin/certbot /usr/bin/certbot &>/dev/null || true
    
    log_info "损坏的 Certbot 已移除"
}

verify_certbot_installation() {
    log_info "验证 Certbot 安装..."
    
    if command -v certbot &>/dev/null; then
        certbot_version=$(certbot --version 2>&1 | head -1)
        log_success "Certbot 安装成功: $certbot_version"
        
        if certbot --help &>/dev/null; then
            log_success "Certbot 功能验证通过"
            CERTBOT_INSTALLED=true
            
            if certbot plugins 2>/dev/null | grep -q nginx; then
                log_success "Nginx 插件可用"
            else
                log_warn "Nginx 插件不可用，但基本功能正常"
            fi
            
            certbot_path=$(which certbot)
            log_info "Certbot 安装路径: $certbot_path"
            
        else
            log_warn "Certbot 安装但功能测试失败"
            CERTBOT_INSTALLED=false
        fi
    else
        log_warn "Certbot 安装失败，将跳过 SSL 证书配置"
        CERTBOT_INSTALLED=false
        
        echo -e "\n${YELLOW}Certbot 安装故障排除：${NC}"
        echo -e "1. 手动安装 Certbot："
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            echo -e "   apt update && apt install -y certbot"
        elif [ "$PACKAGE_MANAGER" = "yum" ]; then
            echo -e "   yum install -y epel-release && yum install -y certbot"
        fi
        echo -e "2. 使用 pip 安装：python3 -m pip install certbot"
        echo -e "3. 使用 snap 安装：snap install --classic certbot"
        echo -e "4. 稍后手动配置 HTTPS"
    fi
}

check_certbot_update() {
    if [ "$CERTBOT_INSTALLED" = true ]; then
        log_info "检查 Certbot 更新..."
        
        if command -v snap &>/dev/null && snap list | grep -q certbot; then
            snap refresh certbot &>/dev/null || true
        elif python3 -m pip show certbot &>/dev/null; then
            python3 -m pip install --upgrade certbot &>/dev/null || true
        else
            if [ "$PACKAGE_MANAGER" = "yum" ]; then
                $PACKAGE_MANAGER update -y certbot &>/dev/null || true
            elif [ "$PACKAGE_MANAGER" = "apt" ]; then
                apt update &>/dev/null && apt upgrade -y certbot &>/dev/null || true
            fi
        fi
        
        new_version=$(certbot --version 2>&1 | head -1)
        log_info "Certbot 版本: $new_version"
    fi
}

setup_firewall() {
    if [ "$FIREWALL_CONFIGURED" = true ]; then
        log_success "防火墙已正确配置，跳过配置步骤"
        show_firewall_status
        return 0
    fi

    log_step "配置防火墙"

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        setup_firewalld
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        setup_ufw
    fi

    verify_firewall_configuration

    show_cloud_security_reminder
}

setup_firewalld() {
    log_info "配置 firewalld..."

    if ! command -v firewall-cmd &>/dev/null; then
        log_info "安装 firewalld..."
        $PACKAGE_MANAGER install -y firewalld || {
            log_warn "firewalld 安装失败，跳过防火墙配置"
            return 1
        }
    fi

    if ! systemctl is-active --quiet firewalld; then
        log_info "启动 firewalld 服务..."
        systemctl start firewalld || {
            log_warn "firewalld 启动失败"
            return 1
        }
    fi

    if ! systemctl is-enabled --quiet firewalld; then
        log_info "启用 firewalld 自启动..."
        systemctl enable firewalld
    fi

    current_ports=$(firewall-cmd --list-ports 2>/dev/null || echo "")
    current_services=$(firewall-cmd --list-services 2>/dev/null || echo "")

    log_info "当前防火墙状态:"
    log_info "  开放端口: $current_ports"
    log_info "  开放服务: $current_services"

    configure_firewalld_rules

    firewall-cmd --reload || {
        log_warn "防火墙重新加载失败，但配置已应用"
    }

    log_success "firewalld 配置完成"
}

configure_firewalld_rules() {
    local rules_changed=false

    required_ports=("22/tcp" "80/tcp" "443/tcp" "$APP_PORT/tcp")
    required_services=("ssh" "http" "https")

    for port in "${required_ports[@]}"; do
        if ! firewall-cmd --list-ports | grep -q "$port"; then
            log_info "开放端口: $port"
            if firewall-cmd --permanent --add-port="$port"; then
                rules_changed=true
                log_success "端口 $port 配置成功"
            else
                log_warn "端口 $port 配置失败"
            fi
        else
            log_info "端口 $port 已开放"
        fi
    done

    for service in "${required_services[@]}"; do
        if ! firewall-cmd --list-services | grep -q "$service"; then
            log_info "开放服务: $service"
            if firewall-cmd --permanent --add-service="$service"; then
                rules_changed=true
                log_success "服务 $service 配置成功"
            else
                log_warn "服务 $service 配置失败"
            fi
        else
            log_info "服务 $service 已开放"
        fi
    done

    if [ "$DOCKER_INSTALLED" = true ]; then
        configure_firewalld_docker
    fi

    if [ "$rules_changed" = true ]; then
        log_info "防火墙规则已更新"
    else
        log_info "防火墙规则无需更新"
    fi
}

configure_firewalld_docker() {
    log_info "配置 Docker 网络规则..."

    if ! firewall-cmd --list-rich-rules | grep -q "docker0"; then
        firewall-cmd --permanent --zone=trusted --add-interface=docker0 2>/dev/null || true
        log_info "添加 Docker 网络接口到信任区域"
    fi

    if ! firewall-cmd --list-sources | grep -q "172.17.0.0/16"; then
        firewall-cmd --permanent --zone=trusted --add-source=172.17.0.0/16 2>/dev/null || true
        log_info "添加 Docker 网络段到信任区域"
    fi
}

setup_ufw() {
    log_info "配置 ufw..."

    if ! command -v ufw &>/dev/null; then
        log_info "安装 ufw..."
        apt install -y ufw || {
            log_warn "ufw 安装失败，跳过防火墙配置"
            return 1
        }
    fi

    ufw_status=$(ufw status | head -1)
    log_info "当前 ufw 状态: $ufw_status"

    if ! ufw status | grep -q "Status: active"; then
        log_info "配置 ufw 默认策略..."
        ufw --force default deny incoming
        ufw --force default allow outgoing

        configure_ufw_rules

        log_info "启用 ufw..."
        ufw --force enable
    else
        log_info "ufw 已启用，检查规则配置..."
        configure_ufw_rules
    fi

    log_success "ufw 配置完成"
}

configure_ufw_rules() {
    local rules_changed=false

    required_ports=("22/tcp" "80/tcp" "443/tcp" "$APP_PORT/tcp")

    for port in "${required_ports[@]}"; do
        port_num=$(echo "$port" | cut -d'/' -f1)
        protocol=$(echo "$port" | cut -d'/' -f2)
        
        if ! ufw status | grep -q "$port_num/$protocol"; then
            log_info "开放端口: $port"
            if ufw allow "$port"; then
                rules_changed=true
                log_success "端口 $port 配置成功"
            else
                log_warn "端口 $port 配置失败"
            fi
        else
            log_info "端口 $port 已开放"
        fi
    done

    if [ "$DOCKER_INSTALLED" = true ]; then
        configure_ufw_docker
    fi

    if [ "$rules_changed" = true ]; then
        log_info "防火墙规则已更新"
        ufw reload &>/dev/null || true
    else
        log_info "防火墙规则无需更新"
    fi
}

configure_ufw_docker() {
    log_info "配置 Docker 网络规则..."

    if ! ufw status | grep -q "172.17.0.0/16"; then
        ufw allow from 172.17.0.0/16 &>/dev/null || true
        log_info "添加 Docker 网络段规则"
    fi

    if ! ufw status | grep -q "127.0.0.1"; then
        ufw allow from 127.0.0.1 &>/dev/null || true
        log_info "添加本地回环规则"
    fi
}

verify_firewall_configuration() {
    log_info "验证防火墙配置..."

    local verification_passed=true

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        if systemctl is-active --quiet firewalld; then
            log_success "✅ firewalld 服务运行正常"
            
            for port in "22/tcp" "80/tcp" "443/tcp" "$APP_PORT/tcp"; do
                if firewall-cmd --list-ports | grep -q "$port" || firewall-cmd --list-services | grep -q "$(echo $port | cut -d'/' -f1)"; then
                    log_success "✅ 端口 $port 已开放"
                else
                    log_warn "⚠️ 端口 $port 未正确开放"
                    verification_passed=false
                fi
            done
        else
            log_warn "⚠️ firewalld 服务未运行"
            verification_passed=false
        fi

    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        if ufw status | grep -q "Status: active"; then
            log_success "✅ ufw 已启用"
            
            for port in "22/tcp" "80/tcp" "443/tcp" "$APP_PORT/tcp"; do
                port_num=$(echo "$port" | cut -d'/' -f1)
                if ufw status | grep -q "$port_num"; then
                    log_success "✅ 端口 $port 已开放"
                else
                    log_warn "⚠️ 端口 $port 未正确开放"
                    verification_passed=false
                fi
            done
        else
            log_warn "⚠️ ufw 未启用"
            verification_passed=false
        fi
    fi

    if [ "$verification_passed" = true ]; then
        log_success "防火墙配置验证通过"
        FIREWALL_CONFIGURED=true
    else
        log_warn "防火墙配置验证失败，但基本功能可用"
        FIREWALL_CONFIGURED=false
    fi
}

show_firewall_status() {
    log_info "当前防火墙状态:"

    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        if systemctl is-active --quiet firewalld; then
            echo -e "  ${GREEN}firewalld: 运行中${NC}"
            echo -e "  开放端口: $(firewall-cmd --list-ports)"
            echo -e "  开放服务: $(firewall-cmd --list-services)"
        else
            echo -e "  ${YELLOW}firewalld: 未运行${NC}"
        fi
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        ufw_status=$(ufw status 2>/dev/null | head -1 || echo "未知")
        echo -e "  ${GREEN}ufw: $ufw_status${NC}"
        if ufw status | grep -q "Status: active"; then
            echo -e "  已开放端口:"
            ufw status | grep -E "^[0-9]+" | while read line; do
                echo -e "    $line"
            done
        fi
    fi
}

show_cloud_security_reminder() {
    echo -e "\n${YELLOW}🔥 重要提醒：云服务器安全组配置${NC}"
    echo -e "${CYAN}请确保在云服务商控制台配置以下安全组规则：${NC}"
    
    echo -e "\n${CYAN}📋 必须开放的端口：${NC}"
    echo -e "   • ${GREEN}TCP:22${NC}   - SSH 管理端口"
    echo -e "   • ${GREEN}TCP:80${NC}   - HTTP 访问端口"
    echo -e "   • ${GREEN}TCP:443${NC}  - HTTPS 访问端口"
    echo -e "   • ${GREEN}TCP:$APP_PORT${NC}  - 应用服务端口 (可选，用于调试)"
    
    echo -e "\n${CYAN}📝 配置说明：${NC}"
    echo -e "   • 协议类型：TCP"
    echo -e "   • 来源地址：${YELLOW}0.0.0.0/0${NC} (允许所有IP访问)"
    echo -e "   • 授权策略：${GREEN}允许${NC}"
    
    echo -e "\n${CYAN}🌍 常见云服务商配置位置：${NC}"
    echo -e "   • 阿里云：ECS控制台 → 安全组"
    echo -e "   • 腾讯云：CVM控制台 → 安全组"
    echo -e "   • 华为云：ECS控制台 → 安全组"
    echo -e "   • AWS：EC2控制台 → Security Groups"
    
    echo -e "\n${YELLOW}⚠️ 注意事项：${NC}"
    echo -e "   • 安全组规则优先级高于系统防火墙"
    echo -e "   • 两者都需要正确配置才能正常访问"
    echo -e "   • 建议先配置安全组，再测试连接"
    
    echo -e "\n${CYAN}🔍 测试连通性：${NC}"
    echo -e "   • 本地测试：${YELLOW}curl http://127.0.0.1/health${NC}"
    echo -e "   • 外网测试：${YELLOW}curl http://你的域名/health${NC}"
    echo -e "   • 端口测试：${YELLOW}telnet 你的IP 80${NC}"
    
    echo -e "\n按 Enter 继续..."
    read
}

open_debug_ports() {
    log_info "临时开放调试端口..."
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        firewall-cmd --add-port=8080/tcp --timeout=3600 &>/dev/null || true
        firewall-cmd --add-port=3000/tcp --timeout=3600 &>/dev/null || true
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        log_warn "如需调试，请手动开放端口：ufw allow 8080"
    fi
}

close_debug_ports() {
    log_info "关闭调试端口..."
    
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        firewall-cmd --remove-port=8080/tcp &>/dev/null || true
        firewall-cmd --remove-port=3000/tcp &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        ufw delete allow 8080 &>/dev/null || true
        ufw delete allow 3000 &>/dev/null || true
    fi
}

clone_project() {
    if [ "$PROJECT_EXISTS" = true ]; then
        log_success "项目代码已存在且完整，跳过克隆步骤"
        cd $PROJECT_DIR
        show_project_info
        ensure_project_structure
        return 0
    fi

    log_step "准备项目代码"

    if [ ! -d "$PROJECT_DIR" ]; then
        mkdir -p $PROJECT_DIR
        log_info "创建项目目录: $PROJECT_DIR"
    fi
    
    cd $PROJECT_DIR

    check_and_handle_existing_project

    if [ "$PROJECT_EXISTS" != true ]; then
        acquire_project_code
    fi

    verify_project_structure

    setup_project_structure

    log_success "项目代码准备完成"
}

check_and_handle_existing_project() {
    log_info "检查现有项目状态..."

    if [ -d ".git" ]; then
        log_info "检测到 Git 仓库"
        handle_git_repository
        return
    fi

    if [ -f "go.mod" ] || [ -f "cmd/server/main.go" ]; then
        log_info "检测到部分项目文件"
        handle_partial_project
        return
    fi

    check_uploaded_packages

    if [ "$(ls -A . 2>/dev/null)" ]; then
        log_warn "目录不为空，备份现有内容..."
        backup_existing_content
    fi
}

handle_git_repository() {
    local current_remote=$(git remote get-url origin 2>/dev/null || echo "")
    log_info "当前远程仓库: $current_remote"

    if [[ "$current_remote" == *"huage"* ]] || [[ "$current_remote" == "$GIT_REPO" ]]; then
        log_info "Git 仓库匹配，检查项目完整性..."
        
        if check_project_completeness; then
            log_success "项目完整，尝试更新代码..."
            update_git_repository
            PROJECT_EXISTS=true
            return
        else
            log_warn "项目不完整，重新克隆..."
            backup_and_reclone
        fi
    else
        log_warn "Git 仓库不匹配"
        echo -e "  当前: $current_remote"
        echo -e "  期望: $GIT_REPO"
        
        echo -e "\n${CYAN}是否使用现有项目？ (y/N):${NC}"
        read -p "> " USE_EXISTING
        
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            if check_project_completeness; then
                PROJECT_EXISTS=true
                return
            fi
        fi
        
        backup_and_reclone
    fi
}

update_git_repository() {
    log_info "更新 Git 仓库..."
    
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_warn "检测到本地修改，创建备份..."
        git stash push -m "Auto backup before update $(date +%Y%m%d_%H%M%S)" || true
    fi
    
    if git fetch origin; then
        local current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        local default_branch="main"
        
        if git show-ref --verify --quiet refs/remotes/origin/main; then
            default_branch="main"
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            default_branch="master"
        fi
        
        log_info "切换到分支: $default_branch"
        if git checkout $default_branch && git pull origin $default_branch; then
            log_success "代码更新成功"
            
            local last_commit=$(git log --oneline -1 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            log_info "最新提交: $last_commit"
        else
            log_warn "代码更新失败，使用现有版本"
        fi
    else
        log_warn "获取远程更新失败，使用现有版本"
    fi
}

backup_and_reclone() {
    log_info "备份现有内容并重新克隆..."
    
    local backup_dir="../$(basename $PROJECT_DIR).backup.$(date +%Y%m%d_%H%M%S)"
    
    cd ..
    if mv "$PROJECT_DIR" "$backup_dir"; then
        log_info "现有内容已备份到: $backup_dir"
        mkdir -p "$PROJECT_DIR"
        cd "$PROJECT_DIR"
        
        clone_from_git
    else
        log_error "备份失败"
        exit 1
    fi
}

handle_partial_project() {
    log_info "处理部分项目文件..."
    
    if check_project_completeness; then
        log_success "项目文件完整"
        PROJECT_EXISTS=true
    else
        log_warn "项目文件不完整，尝试补全..."
        
        if [ -f "go.mod" ] && [ ! -f "cmd/server/main.go" ]; then
            log_info "尝试从Git仓库补全文件..."
            init_git_and_pull
        else
            log_warn "无法自动补全，将重新获取代码"
            backup_existing_content
        fi
    fi
}

init_git_and_pull() {
    if git init && git remote add origin "$GIT_REPO"; then
        if git fetch origin && git checkout -b main origin/main; then
            log_success "项目补全成功"
            PROJECT_EXISTS=true
        else
            log_warn "从Git补全失败"
        fi
    fi
}

check_uploaded_packages() {
    log_info "检查上传的项目包..."
    
    local package_locations=(
        "/opt/notes-backend.tar.gz"
        "/opt/notes-backend.zip"
        "/tmp/notes-backend.tar.gz"
        "/tmp/notes-backend.zip"
        "./notes-backend.tar.gz"
        "./notes-backend.zip"
    )
    
    for package_path in "${package_locations[@]}"; do
        if [ -f "$package_path" ]; then
            log_info "找到压缩包: $package_path"
            extract_package "$package_path"
            return
        fi
    done
    
    local upload_dirs=(
        "/opt/notes-backend-uploaded"
        "/tmp/notes-backend-uploaded"
        "./notes-backend-uploaded"
    )
    
    for upload_dir in "${upload_dirs[@]}"; do
        if [ -d "$upload_dir" ]; then
            log_info "找到上传目录: $upload_dir"
            copy_uploaded_files "$upload_dir"
            return
        fi
    done
}

extract_package() {
    local package_path="$1"
    local package_name=$(basename "$package_path")
    
    log_info "解压项目包: $package_name"
    
    case "$package_path" in
        *.tar.gz)
            if tar -xzf "$package_path" --strip-components=1 2>/dev/null || tar -xzf "$package_path"; then
                log_success "tar.gz 解压成功"
            else
                log_warn "tar.gz 解压失败"
                return 1
            fi
            ;;
        *.zip)
            if command -v unzip &>/dev/null; then
                if unzip -q "$package_path" -d ./temp_extract && mv ./temp_extract/*/* . 2>/dev/null; then
                    rm -rf ./temp_extract
                    log_success "zip 解压成功"
                else
                    unzip -q "$package_path" && log_success "zip 解压成功"
                fi
            else
                log_warn "unzip 命令不可用"
                return 1
            fi
            ;;
        *)
            log_warn "不支持的压缩格式: $package_name"
            return 1
            ;;
    esac
    
    if check_project_completeness; then
        PROJECT_EXISTS=true
        log_success "项目包解压并验证完成"
        
        rm -f "$package_path"
    else
        log_warn "解压的项目不完整"
    fi
}

copy_uploaded_files() {
    local upload_dir="$1"
    
    log_info "复制上传的项目文件..."
    
    if cp -r "$upload_dir"/* . 2>/dev/null || cp -r "$upload_dir"/. .; then
        log_success "文件复制成功"
        
        if check_project_completeness; then
            PROJECT_EXISTS=true
            log_success "上传项目验证完成"
            
            rm -rf "$upload_dir"
        else
            log_warn "上传的项目不完整"
        fi
    else
        log_warn "文件复制失败"
    fi
}

backup_existing_content() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="../$(basename $PROJECT_DIR).backup.$timestamp"
    
    log_info "备份现有内容到: $backup_dir"
    
    cd ..
    if mv "$PROJECT_DIR" "$backup_dir"; then
        mkdir -p "$PROJECT_DIR"
        cd "$PROJECT_DIR"
        log_success "备份完成"
    else
        cd "$PROJECT_DIR"
        mkdir -p "./backup.$timestamp"
        mv ./* "./backup.$timestamp/" 2>/dev/null || true
        mv ./.* "./backup.$timestamp/" 2>/dev/null || true
        log_info "本地备份完成"
    fi
}

acquire_project_code() {
    log_info "获取项目代码..."
    
    if clone_from_git; then
        return
    fi
    
    show_acquisition_alternatives
}

clone_from_git() {
    log_info "从 Git 仓库克隆项目..."
    log_info "仓库地址: $GIT_REPO"
    
    if git clone "$GIT_REPO" .; then
        log_success "Git 克隆成功"
        
        if check_project_completeness; then
            PROJECT_EXISTS=true
            return 0
        else
            log_warn "克隆的项目不完整"
            return 1
        fi
    else
        log_warn "Git 克隆失败"
        return 1
    fi
}

check_project_completeness() {
    local required_files=("go.mod" "cmd/server/main.go")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        return 0  # 完整
    else
        log_warn "缺少关键文件: ${missing_files[*]}"
        return 1  # 不完整
    fi
}

verify_project_structure() {
    log_info "验证项目结构..."
    
    local required_files=("go.mod" "cmd/server/main.go")
    local optional_files=("README.md" "Dockerfile" ".env.example")
    local required_dirs=("internal" "cmd")
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "项目结构不完整，缺少关键文件："
        for file in "${missing_files[@]}"; do
            echo -e "   ❌ $file"
        done
        
        show_project_structure_help
        exit 1
    fi
    
    log_success "✅ 必需文件验证通过"
    
    for file in "${optional_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "✅ $file"
        else
            log_info "⚠️ $file (可选)"
        fi
    done
    
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "✅ $dir/"
        else
            log_warn "⚠️ $dir/ (目录缺失)"
        fi
    done
    
    PROJECT_EXISTS=true
    log_success "项目结构验证通过"
}

setup_project_structure() {
    log_info "设置项目目录结构..."
    
    local required_dirs=("uploads" "logs" "nginx" "backup" "scripts")
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir/"
        fi
    done
    
    chmod -R 755 uploads logs backup scripts 2>/dev/null || true
    
    for dir in uploads logs backup; do
        if [ ! -f "$dir/.gitkeep" ]; then
            touch "$dir/.gitkeep"
        fi
    done
    
    log_success "项目目录结构设置完成"
}

show_project_info() {
    log_info "项目信息："
    
    if [ -f "go.mod" ]; then
        local project_name=$(head -1 go.mod | awk '{print $2}')
        log_info "  项目名称: $project_name"
    fi
    
    if [ -d ".git" ]; then
        local current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        local last_commit=$(git log --oneline -1 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        log_info "  Git 分支: $current_branch"
        log_info "  最后提交: $last_commit"
    fi
    
    if [ -f "notes-backend" ]; then
        local file_size=$(du -h notes-backend | cut -f1)
        log_info "  编译状态: 已编译 ($file_size)"
    else
        log_info "  编译状态: 未编译"
    fi
}

ensure_project_structure() {
    setup_project_structure
}

show_acquisition_alternatives() {
    log_error "无法从 Git 仓库获取项目代码"
    
    echo -e "\n${YELLOW}📁 替代解决方案：${NC}"
    echo -e "\n${CYAN}方案 1: 手动上传项目文件${NC}"
    echo -e "1. 在本地打包项目："
    echo -e "   ${YELLOW}tar -czf notes-backend.tar.gz --exclude='.git' .${NC}"
    echo -e "2. 上传到服务器："
    echo -e "   ${YELLOW}scp notes-backend.tar.gz root@server:/opt/${NC}"
    echo -e "3. 重新运行脚本"
    
    echo -e "\n${CYAN}方案 2: 直接在当前目录放置文件${NC}"
    echo -e "1. 将项目文件复制到: ${YELLOW}$PROJECT_DIR${NC}"
    echo -e "2. 确保包含关键文件: ${YELLOW}go.mod, cmd/server/main.go${NC}"
    echo -e "3. 重新运行脚本"
    
    echo -e "\n${CYAN}方案 3: 使用其他 Git 仓库${NC}"
    echo -e "1. 准备可访问的 Git 仓库"
    echo -e "2. 重新运行脚本并输入新的仓库地址"
    
    echo -e "\n${CYAN}方案 4: 解决网络问题${NC}"
    echo -e "1. 检查网络连接：${YELLOW}ping -c 3 github.com${NC}"
    echo -e "2. 配置代理或更换网络环境"
    echo -e "3. 使用 SSH 方式克隆"
    
    exit 1
}

show_project_structure_help() {
    echo -e "\n${YELLOW}📋 正确的项目结构示例：${NC}"
    cat << 'EOF'
notes-backend/
├── go.mod                 # Go 模块文件 (必需)
├── go.sum                 # Go 依赖校验文件
├── cmd/
│   └── server/
│       └── main.go        # 主程序入口 (必需)
├── internal/              # 内部包目录
│   ├── config/
│   ├── database/
│   ├── handlers/
│   ├── models/
│   └── services/
├── README.md              # 项目说明
└── Dockerfile             # Docker 构建文件
EOF
    
    echo -e "\n${CYAN}🔧 如何修复：${NC}"
    echo -e "1. 确保上传了完整的项目文件"
    echo -e "2. 检查项目目录结构是否正确"
    echo -e "3. 重新下载或克隆完整项目"
}

compile_application() {
    cd $PROJECT_DIR

    if check_compilation_needed; then
        log_step "编译 Go 应用"
        perform_compilation
    else
        log_success "应用已是最新编译版本，跳过编译步骤"
        verify_binary_functionality
        return 0
    fi
}

check_compilation_needed() {
    log_info "检查编译状态..."

    if [ ! -f "notes-backend" ]; then
        log_info "二进制文件不存在，需要编译"
        return 0  # 需要编译
    fi

    if [ ! -x "notes-backend" ]; then
        log_warn "二进制文件不可执行，需要重新编译"
        return 0  # 需要编译
    fi

    local binary_time=$(stat -c %Y "notes-backend" 2>/dev/null || stat -f %m "notes-backend" 2>/dev/null || echo "0")
    
    if check_source_changes "$binary_time"; then
        log_info "源码有更新，需要重新编译"
        return 0  # 需要编译
    fi

    if check_dependencies_changed "$binary_time"; then
        log_info "依赖有变化，需要重新编译"
        return 0  # 需要编译
    fi

    if check_go_version_compatibility; then
        log_info "Go版本兼容，无需重新编译"
    else
        log_info "Go版本不兼容，需要重新编译"
        return 0  # 需要编译
    fi

    if test_binary_basic_function; then
        log_success "现有二进制文件功能正常"
        return 1  # 不需要编译
    else
        log_warn "现有二进制文件功能异常，需要重新编译"
        return 0  # 需要编译
    fi
}

check_source_changes() {
    local binary_time="$1"
    
    local source_files=(
        "cmd/server/main.go"
        "go.mod"
        "go.sum"
    )
    
    if [ -d "internal" ]; then
        while IFS= read -r -d '' file; do
            source_files+=("$file")
        done < <(find internal -name "*.go" -print0 2>/dev/null)
    fi
    
    for file in "${source_files[@]}"; do
        if [ -f "$file" ]; then
            local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
            if [ "$file_time" -gt "$binary_time" ]; then
                log_info "文件已更新: $file"
                return 0  # 有变化
            fi
        fi
    done
    
    return 1  # 无变化
}

check_dependencies_changed() {
    local binary_time="$1"
    
    for file in "go.mod" "go.sum"; do
        if [ -f "$file" ]; then
            local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
            if [ "$file_time" -gt "$binary_time" ]; then
                log_info "依赖文件已更新: $file"
                return 0  # 有变化
            fi
        fi
    done
    
    return 1  # 无变化
}

check_go_version_compatibility() {
    if [ ! -f "notes-backend" ]; then
        return 1  # 不兼容
    fi
    
    local binary_info=$(./notes-backend --version 2>/dev/null || ./notes-backend -v 2>/dev/null || echo "")
    
    if [ -n "$binary_info" ]; then
        return 0  # 兼容
    fi
    
    if command -v file &>/dev/null; then
        local file_info=$(file "notes-backend")
        local current_arch=$(uname -m)
        
        case "$current_arch" in
            "x86_64")
                if echo "$file_info" | grep -q "x86-64"; then
                    return 0  # 兼容
                fi
                ;;
            "aarch64"|"arm64")
                if echo "$file_info" | grep -q "aarch64\|ARM"; then
                    return 0  # 兼容
                fi
                ;;
        esac
    fi
    
    return 1  # 不兼容
}

test_binary_basic_function() {
    log_info "测试现有二进制文件..."
    
    if [ ! -x "notes-backend" ]; then
        log_warn "二进制文件无执行权限"
        chmod +x "notes-backend" 2>/dev/null || return 1
    fi
    
    if timeout 10 ./notes-backend --help &>/dev/null || timeout 10 ./notes-backend -h &>/dev/null; then
        log_success "二进制文件响应正常"
        return 0
    fi
    
    if timeout 5 ./notes-backend --version &>/dev/null || timeout 5 ./notes-backend -v &>/dev/null; then
        log_success "二进制文件版本查询正常"
        return 0
    fi
    
    if command -v file &>/dev/null; then
        local file_type=$(file "notes-backend")
        if echo "$file_type" | grep -q "ELF.*executable"; then
            log_info "二进制文件格式正确"
            return 0
        else
            log_warn "二进制文件格式异常: $file_type"
            return 1
        fi
    fi
    
    log_warn "无法验证二进制文件功能"
    return 1
}

perform_compilation() {
    setup_go_environment_for_build

    verify_go_environment

    handle_dependencies

    backup_existing_binary

    execute_build

    verify_compilation_result
}

setup_go_environment_for_build() {
    log_info "设置编译环境..."
    
    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on
    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=$GO_ARCH
    
    export GOFLAGS="-trimpath"
    
    log_info "Go环境变量:"
    log_info "  GOPROXY: $GOPROXY"
    log_info "  GO111MODULE: $GO111MODULE"
    log_info "  CGO_ENABLED: $CGO_ENABLED"
    log_info "  GOOS: $GOOS"
    log_info "  GOARCH: $GOARCH"
}

verify_go_environment() {
    log_info "验证Go环境..."
    
    if ! command -v go &>/dev/null; then
        log_error "Go命令不可用"
        exit 1
    fi
    
    local go_version=$(go version)
    log_info "Go版本: $go_version"
    
    if [ ! -f "go.mod" ]; then
        log_error "未找到 go.mod 文件"
        exit 1
    fi
    
    local module_name=$(head -1 go.mod | awk '{print $2}')
    log_info "项目模块: $module_name"
    
    if [ ! -f "cmd/server/main.go" ]; then
        log_error "未找到主程序入口: cmd/server/main.go"
        exit 1
    fi
    
    log_success "Go环境验证通过"
}

handle_dependencies() {
    log_info "处理项目依赖..."
    
    if ! ping -c 1 goproxy.cn &>/dev/null && ! ping -c 1 proxy.golang.org &>/dev/null; then
        log_warn "Go代理连接异常，可能影响依赖下载"
    fi
    
    log_info "下载Go依赖..."
    if go mod download; then
        log_success "依赖下载完成"
    else
        log_error "依赖下载失败"
        
        echo -e "\n${YELLOW}依赖下载故障排除：${NC}"
        echo -e "1. 检查网络连接：ping goproxy.cn"
        echo -e "2. 清理模块缓存：go clean -modcache"
        echo -e "3. 验证go.mod格式：go mod verify"
        echo -e "4. 手动整理依赖：go mod tidy"
        
        exit 1
    fi
    
    log_info "整理依赖关系..."
    if go mod tidy; then
        log_success "依赖整理完成"
    else
        log_warn "依赖整理失败，但继续编译"
    fi
    
    if go mod verify; then
        log_success "依赖验证通过"
    else
        log_warn "依赖验证失败，但继续编译"
    fi
}

backup_existing_binary() {
    if [ -f "notes-backend" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name="notes-backend.backup.$timestamp"
        
        log_info "备份现有二进制文件: $backup_name"
        cp "notes-backend" "$backup_name" || {
            log_warn "备份失败，继续编译"
        }
    fi
}

execute_build() {
    log_info "开始编译应用程序..."
    
    local version=$(git describe --tags --always --dirty 2>/dev/null || echo "unknown")
    local build_time=$(date +"%Y-%m-%d %H:%M:%S")
    local git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    local ldflags="-w -s"
    ldflags="$ldflags -X 'main.Version=$version'"
    ldflags="$ldflags -X 'main.BuildTime=$build_time'"
    ldflags="$ldflags -X 'main.GitCommit=$git_commit'"
    
    log_info "编译信息:"
    log_info "  版本: $version"
    log_info "  构建时间: $build_time"
    log_info "  Git提交: $git_commit"
    
    echo -e "${CYAN}编译进度:${NC}"
    
    if go build -ldflags="$ldflags" -trimpath -o notes-backend cmd/server/main.go; then
        log_success "应用编译成功"
        
        chmod +x notes-backend
        
        local file_size=$(du -h notes-backend | cut -f1)
        log_info "二进制文件大小: $file_size"
        
        if command -v file &>/dev/null; then
            local file_info=$(file notes-backend)
            log_info "文件类型: $file_info"
        fi
        
    else
        log_error "应用编译失败"
        show_compilation_troubleshooting
        exit 1
    fi
}

verify_compilation_result() {
    log_info "验证编译结果..."
    
    if [ ! -f "notes-backend" ]; then
        log_error "编译后的二进制文件不存在"
        exit 1
    fi
    
    if [ ! -x "notes-backend" ]; then
        log_warn "二进制文件无执行权限，正在修复..."
        chmod +x notes-backend
    fi
    
    log_info "测试二进制文件基本功能..."
    if timeout 10 ./notes-backend --help &>/dev/null || timeout 10 ./notes-backend -h &>/dev/null; then
        log_success "✅ 帮助信息测试通过"
    else
        log_warn "⚠️ 帮助信息测试失败，但文件已生成"
    fi
    
    if timeout 5 ./notes-backend --version &>/dev/null; then
        local version_info=$(timeout 5 ./notes-backend --version 2>/dev/null || echo "无版本信息")
        log_success "✅ 版本信息: $version_info"
    else
        log_info "⚠️ 版本信息不可用"
    fi
    
    if command -v file &>/dev/null; then
        local file_type=$(file notes-backend)
        if echo "$file_type" | grep -q "executable"; then
            log_success "✅ 文件格式验证通过"
        else
            log_warn "⚠️ 文件格式可能异常: $file_type"
        fi
    fi
    
    log_success "编译结果验证完成"
}

verify_binary_functionality() {
    log_info "验证现有二进制文件功能..."
    
    if test_binary_basic_function; then
        log_success "二进制文件功能验证通过"
        
        local file_size=$(du -h notes-backend | cut -f1)
        local file_time=$(stat -c %y notes-backend 2>/dev/null | cut -d'.' -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" notes-backend 2>/dev/null || echo "未知时间")
        
        log_info "文件信息:"
        log_info "  大小: $file_size"
        log_info "  修改时间: $file_time"
        
    else
        log_warn "二进制文件功能异常，建议重新编译"
        echo -e "\n${CYAN}是否强制重新编译？ (y/N):${NC}"
        read -p "> " FORCE_REBUILD
        
        if [[ "$FORCE_REBUILD" =~ ^[Yy]$ ]]; then
            perform_compilation
        fi
    fi
}

show_compilation_troubleshooting() {
    echo -e "\n${YELLOW}编译故障排除：${NC}"
    echo -e "1. ${CYAN}检查Go环境${NC}"
    echo -e "   go version"
    echo -e "   go env GOPROXY"
    echo -e ""
    echo -e "2. ${CYAN}检查项目结构${NC}"
    echo -e "   ls -la cmd/server/main.go"
    echo -e "   cat go.mod"
    echo -e ""
    echo -e "3. ${CYAN}清理并重试${NC}"
    echo -e "   go clean -cache"
    echo -e "   go mod download"
    echo -e "   go mod tidy"
    echo -e ""
    echo -e "4. ${CYAN}手动编译测试${NC}"
    echo -e "   go build -v cmd/server/main.go"
    echo -e ""
    echo -e "5. ${CYAN}检查错误日志${NC}"
    echo -e "   检查上方的具体错误信息"
    echo -e "   常见问题：网络连接、语法错误、依赖缺失"
}

clean_build_cache() {
    log_info "清理编译缓存..."
    
    go clean -cache &>/dev/null || true
    go clean -modcache &>/dev/null || true
    go clean -testcache &>/dev/null || true
    
    log_info "编译缓存清理完成"
}

show_build_stats() {
    if [ -f "notes-backend" ]; then
        echo -e "\n${CYAN}编译统计：${NC}"
        
        local file_size=$(du -h notes-backend | cut -f1)
        local file_size_bytes=$(stat -c %s notes-backend 2>/dev/null || stat -f %z notes-backend 2>/dev/null || echo "0")
        
        echo -e "  文件大小: ${GREEN}$file_size${NC} ($file_size_bytes bytes)"
        
        if command -v file &>/dev/null; then
            local file_info=$(file notes-backend | cut -d':' -f2)
            echo -e "  文件类型:$file_info"
        fi
        
        if command -v ldd &>/dev/null && ldd notes-backend &>/dev/null; then
            echo -e "  依赖库: 静态链接"
        fi
        
        local build_time=$(stat -c %y notes-backend 2>/dev/null | cut -d'.' -f1 || stat -f %Sm -t "%Y-%m-%d %H:%M:%S" notes-backend 2>/dev/null || echo "未知")
        echo -e "  构建时间: ${GREEN}$build_time${NC}"
    fi
}

setup_database() {
    case $DB_TYPE in
        "local")
            setup_local_database_optimized
            ;;
        "vercel")
            setup_vercel_database_optimized
            ;;
        "custom")
            setup_custom_database_optimized
            ;;
        *)
            log_error "未知的数据库类型: $DB_TYPE"
            exit 1
            ;;
    esac
}

setup_local_database_optimized() {
    if [ "$LOCAL_DB_RUNNING" = true ]; then
        log_success "本地数据库已运行正常，跳过设置步骤"
        verify_database_connection "local"
        return 0
    fi

    log_step "配置本地 PostgreSQL 数据库"

    cd $PROJECT_DIR

    configure_docker_registry_mirrors

    check_existing_database_container

    create_database_compose_config

    ensure_postgres_image

    start_database_service

    verify_database_connection "local"

    log_success "本地数据库配置完成"
}

configure_docker_registry_mirrors() {
    if [ -f /etc/docker/daemon.json ]; then
        if grep -q "registry-mirrors" /etc/docker/daemon.json; then
            log_info "Docker镜像加速器已配置"
            return 0
        fi
    fi

    log_info "配置Docker镜像加速器..."
    
    mkdir -p /etc/docker
    
    if [ -f /etc/docker/daemon.json ]; then
        cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
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
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  }
}
EOF
    
    log_info "重启Docker服务以应用镜像加速器..."
    systemctl daemon-reload
    systemctl restart docker
    sleep 5
    
    if systemctl is-active --quiet docker; then
        log_success "Docker镜像加速器配置完成"
    else
        log_warn "Docker重启失败，使用原配置"
        if [ -f /etc/docker/daemon.json.backup.* ]; then
            mv /etc/docker/daemon.json.backup.* /etc/docker/daemon.json
        fi
        systemctl start docker
    fi
}

check_existing_database_container() {
    log_info "检查现有数据库容器..."

    if docker ps -a | grep -q "notes-postgres"; then
        local container_status=$(docker ps -a --filter "name=notes-postgres" --format "{{.Status}}")
        log_info "现有容器状态: $container_status"

        if docker ps | grep -q "notes-postgres"; then
            log_info "数据库容器正在运行，检查连接..."
            
            if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
                log_success "现有数据库连接正常"
                LOCAL_DB_RUNNING=true
                return 0
            else
                log_warn "现有数据库连接异常，将重启容器"
                restart_database_container
                return 0
            fi
        else
            log_info "数据库容器已停止，尝试启动..."
            if docker start notes-postgres; then
                sleep 10
                if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
                    log_success "数据库容器启动成功"
                    LOCAL_DB_RUNNING=true
                    return 0
                fi
            fi
            
            log_warn "无法启动现有容器，将重新创建"
            remove_database_container
        fi
    else
        log_info "未找到现有数据库容器"
    fi
}

restart_database_container() {
    log_info "重启数据库容器..."
    
    docker restart notes-postgres
    sleep 15
    
    if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
        log_success "数据库容器重启成功"
        LOCAL_DB_RUNNING=true
    else
        log_warn "数据库容器重启失败，将重新创建"
        remove_database_container
    fi
}

remove_database_container() {
    log_info "移除旧的数据库容器..."
    
    docker stop notes-postgres 2>/dev/null || true
    docker rm notes-postgres 2>/dev/null || true
    
    log_info "旧容器已移除"
}

create_database_compose_config() {
    if [ -f "docker-compose.db.yml" ] && [ "$LOCAL_DB_RUNNING" = true ]; then
        log_info "数据库配置文件已存在且数据库运行正常"
        return 0
    fi

    log_info "创建数据库Docker Compose配置..."
    
    cat > docker-compose.db.yml << EOF
version: '3.8'

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
      PGDATA: /var/lib/postgresql/data/pgdata
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
               -c logging_collector=on
               -c log_directory=/var/lib/postgresql/data/log
               -c log_filename='postgresql-%Y-%m-%d_%H%M%S.log'
               -c log_rotation_age=1d
               -c log_rotation_size=100MB
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $DB_USER -d $DB_NAME"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  postgres_data:
    driver: local

networks:
  notes-network:
    driver: bridge
EOF

    mkdir -p database/init
    
    if [ ! -f "database/init/01-init.sql" ]; then
        cat > database/init/01-init.sql << EOF
-- 数据库初始化脚本
-- 创建扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 设置时区
SET timezone = 'Asia/Shanghai';

-- 创建用户（如果不存在）
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

-- 授权
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    fi

    log_success "数据库配置文件创建完成"
}

ensure_postgres_image() {
    local image_name="postgres:15-alpine"
    
    log_info "检查PostgreSQL镜像..."
    
    if docker images | grep -q "postgres.*15-alpine"; then
        log_success "PostgreSQL镜像已存在"
        return 0
    fi
    
    log_info "拉取PostgreSQL镜像..."
    
    if docker pull $image_name; then
        log_success "PostgreSQL官方镜像拉取成功"
        return 0
    fi
    
    log_warn "官方镜像拉取失败，尝试国内镜像..."
    
    local mirrors=(
        "registry.cn-hangzhou.aliyuncs.com/library/postgres:15-alpine"
        "dockerhub.azk8s.cn/library/postgres:15-alpine"
        "docker.mirrors.ustc.edu.cn/library/postgres:15-alpine"
    )
    
    for mirror in "${mirrors[@]}"; do
        log_info "尝试镜像: $mirror"
        if docker pull $mirror; then
            docker tag $mirror $image_name
            log_success "国内镜像拉取成功: $mirror"
            return 0
        fi
    done
    
    log_error "无法拉取PostgreSQL镜像，请检查网络连接"
    show_postgres_image_troubleshooting
    exit 1
}

start_database_service() {
    if [ "$LOCAL_DB_RUNNING" = true ]; then
        log_info "数据库已运行，跳过启动"
        return 0
    fi

    log_info "启动PostgreSQL数据库..."
    
    docker compose -f docker-compose.db.yml down 2>/dev/null || true
    
    if docker compose -f docker-compose.db.yml up -d; then
        log_success "数据库容器启动命令执行成功"
    else
        log_error "数据库容器启动失败"
        show_database_logs
        exit 1
    fi

    wait_for_database_ready
}

wait_for_database_ready() {
    log_info "等待数据库启动..."
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
            log_success "数据库启动成功 (耗时: ${attempt}0秒)"
            LOCAL_DB_RUNNING=true
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "数据库启动超时"
            show_database_startup_troubleshooting
            exit 1
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "等待数据库启动... (${attempt}/${max_attempts})"
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log_info "等待数据库完全就绪..."
    sleep 5
}

verify_database_connection() {
    local db_type="$1"
    
    log_info "验证数据库连接..."
    
    case $db_type in
        "local")
            verify_local_database_connection
            ;;
        "vercel")
            verify_vercel_database_connection
            ;;
        "custom")
            verify_custom_database_connection
            ;;
    esac
}

verify_local_database_connection() {
    if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME; then
        log_success "✅ 数据库连接正常"
    else
        log_error "❌ 数据库连接失败"
        return 1
    fi
    
    local db_version=$(docker exec notes-postgres psql -U $DB_USER -d $DB_NAME -t -c "SELECT version();" 2>/dev/null | head -1 | xargs || echo "未知版本")
    log_info "数据库版本: $db_version"
    
    if docker exec notes-postgres psql -U $DB_USER -d $DB_NAME -c "SELECT current_database(), current_user, inet_server_addr(), inet_server_port();" &>/dev/null; then
        log_success "✅ 数据库查询测试通过"
    else
        log_warn "⚠️ 数据库查询测试失败"
    fi
    
    if docker exec notes-postgres psql -U $DB_USER -d $DB_NAME -c "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY); DROP TABLE IF EXISTS test_table;" &>/dev/null; then
        log_success "✅ 数据库权限测试通过"
    else
        log_warn "⚠️ 数据库权限测试失败"
    fi
    
    echo -e "\n${CYAN}数据库连接信息：${NC}"
    echo -e "  主机: localhost"
    echo -e "  端口: 5432"
    echo -e "  数据库: $DB_NAME"
    echo -e "  用户名: $DB_USER"
    echo -e "  容器名: notes-postgres"
}

setup_vercel_database_optimized() {
    log_step "验证 Vercel Postgres 数据库连接"
    
    if [ -z "$VERCEL_POSTGRES_URL" ]; then
        log_error "Vercel数据库连接字符串未配置"
        exit 1
    fi
    
    if [[ ! "$VERCEL_POSTGRES_URL" =~ ^postgresql:// ]]; then
        log_error "Vercel数据库URL格式错误"
        exit 1
    fi
    
    log_info "Vercel数据库URL: ${VERCEL_POSTGRES_URL:0:50}..."
    
    verify_vercel_database_connection
    
    log_success "Vercel数据库配置验证完成"
}

verify_vercel_database_connection() {
    log_info "验证Vercel数据库连接..."
    
    if ! command -v psql &>/dev/null; then
        log_info "安装PostgreSQL客户端..."
        install_postgres_client
    fi
    
    if timeout 30 psql "$VERCEL_POSTGRES_URL" -c "SELECT version();" &>/dev/null; then
        log_success "✅ Vercel数据库连接正常"
        
        local db_info=$(timeout 10 psql "$VERCEL_POSTGRES_URL" -t -c "SELECT current_database(), current_user;" 2>/dev/null | xargs || echo "信息获取失败")
        log_info "数据库信息: $db_info"
        
    else
        log_error "❌ Vercel数据库连接失败"
        echo -e "\n${YELLOW}请检查：${NC}"
        echo -e "1. 数据库URL是否正确"
        echo -e "2. 网络连接是否正常"
        echo -e "3. 数据库是否已创建并启动"
        exit 1
    fi
}

setup_custom_database_optimized() {
    log_step "验证自定义数据库连接"
    
    if [ -z "$CUSTOM_DB_HOST" ] || [ -z "$CUSTOM_DB_USER" ] || [ -z "$CUSTOM_DB_NAME" ]; then
        log_error "自定义数据库配置不完整"
        exit 1
    fi
    
    log_info "自定义数据库配置:"
    log_info "  主机: $CUSTOM_DB_HOST"
    log_info "  端口: $CUSTOM_DB_PORT"
    log_info "  数据库: $CUSTOM_DB_NAME"
    log_info "  用户: $CUSTOM_DB_USER"
    
    verify_custom_database_connection
    
    log_success "自定义数据库配置验证完成"
}

verify_custom_database_connection() {
    log_info "验证自定义数据库连接..."
    
    if ! command -v psql &>/dev/null; then
        log_info "安装PostgreSQL客户端..."
        install_postgres_client
    fi
    
    local custom_dsn="postgresql://$CUSTOM_DB_USER:$CUSTOM_DB_PASSWORD@$CUSTOM_DB_HOST:$CUSTOM_DB_PORT/$CUSTOM_DB_NAME"
    
    if timeout 30 psql "$custom_dsn" -c "SELECT version();" &>/dev/null; then
        log_success "✅ 自定义数据库连接正常"
        
        local db_info=$(timeout 10 psql "$custom_dsn" -t -c "SELECT current_database(), current_user;" 2>/dev/null | xargs || echo "信息获取失败")
        log_info "数据库信息: $db_info"
        
    else
        log_error "❌ 自定义数据库连接失败"
        echo -e "\n${YELLOW}请检查：${NC}"
        echo -e "1. 数据库服务器是否运行"
        echo -e "2. 连接参数是否正确"
        echo -e "3. 网络是否可达"
        echo -e "4. 用户权限是否足够"
        exit 1
    fi
}

install_postgres_client() {
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER install -y postgresql postgresql-contrib || true
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        apt update
        apt install -y postgresql-client postgresql-client-common || true
    fi
    
    if command -v psql &>/dev/null; then
        log_success "PostgreSQL客户端安装成功"
    else
        log_warn "PostgreSQL客户端安装失败，将跳过连接测试"
    fi
}

show_database_logs() {
    echo -e "\n${YELLOW}数据库容器日志：${NC}"
    docker logs notes-postgres --tail 50 2>/dev/null || echo "无法获取容器日志"
    
    echo -e "\n${YELLOW}Docker Compose状态：${NC}"
    docker compose -f docker-compose.db.yml ps 2>/dev/null || echo "无法获取Compose状态"
}

show_postgres_image_troubleshooting() {
    echo -e "\n${YELLOW}PostgreSQL镜像下载故障排除：${NC}"
    echo -e "1. 检查网络连接：ping -c 3 docker.io"
    echo -e "2. 检查Docker状态：systemctl status docker"
    echo -e "3. 清理Docker缓存：docker system prune -f"
    echo -e "4. 手动拉取镜像：docker pull postgres:15-alpine"
    echo -e "5. 使用国内镜像：docker pull registry.cn-hangzhou.aliyuncs.com/library/postgres:15-alpine"
}

show_database_startup_troubleshooting() {
    echo -e "\n${YELLOW}数据库启动故障排除：${NC}"
    echo -e "1. 查看容器状态：docker ps -a | grep postgres"
    echo -e "2. 查看容器日志：docker logs notes-postgres"
    echo -e "3. 检查端口占用：netstat -tlnp | grep 5432"
    echo -e "4. 重启容器：docker restart notes-postgres"
    echo -e "5. 重新创建：docker compose -f docker-compose.db.yml down && docker compose -f docker-compose.db.yml up -d"
    
    show_database_logs
}

create_configuration() {
    if [ "$CONFIG_EXISTS" = true ] && validate_existing_configuration; then
        log_success "配置文件已存在且有效，跳过创建步骤"
        show_configuration_summary
        return 0
    fi

    log_step "创建配置文件"

    cd $PROJECT_DIR

    backup_existing_configuration

    create_env_configuration

    create_nginx_configurations

    validate_configuration_files

    set_configuration_permissions

    log_success "配置文件创建完成"
    show_configuration_summary
}

validate_existing_configuration() {
    log_info "验证现有配置文件..."

    if [ ! -f ".env" ]; then
        log_warn ".env文件不存在"
        return 1
    fi

    if ! grep -q "=" ".env"; then
        log_warn ".env文件格式无效"
        return 1
    fi

    local validation_failed=false

    if ! validate_database_config_in_env; then
        validation_failed=true
    fi

    if ! validate_basic_config_in_env; then
        validation_failed=true
    fi

    if ! validate_nginx_config_files; then
        validation_failed=true
    fi

    if [ "$validation_failed" = true ]; then
        log_warn "现有配置验证失败，将重新创建"
        return 1
    fi

    log_success "现有配置验证通过"
    return 0
}

validate_database_config_in_env() {
    source .env 2>/dev/null || return 1

    case "$DB_MODE" in
        "local")
            if [ -z "$LOCAL_DB_USER" ] || [ -z "$LOCAL_DB_PASSWORD" ] || [ -z "$LOCAL_DB_NAME" ]; then
                log_warn "本地数据库配置不完整"
                return 1
            fi
            ;;
        "vercel")
            if [ -z "$VERCEL_POSTGRES_URL" ]; then
                log_warn "Vercel数据库URL未配置"
                return 1
            fi
            if [[ ! "$VERCEL_POSTGRES_URL" =~ ^postgresql:// ]]; then
                log_warn "Vercel数据库URL格式错误"
                return 1
            fi
            ;;
        "custom")
            if [ -z "$CUSTOM_DB_HOST" ] || [ -z "$CUSTOM_DB_USER" ] || [ -z "$CUSTOM_DB_NAME" ]; then
                log_warn "自定义数据库配置不完整"
                return 1
            fi
            ;;
        *)
            log_warn "未知的数据库模式: $DB_MODE"
            return 1
            ;;
    esac

    return 0
}

validate_basic_config_in_env() {
    source .env 2>/dev/null || return 1

    if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 16 ]; then
        log_warn "JWT密钥无效或太短"
        return 1
    fi

    if [ -z "$SERVER_PORT" ] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
        log_warn "服务端口配置无效"
        return 1
    fi

    if [ -z "$FRONTEND_BASE_URL" ]; then
        log_warn "前端URL未配置"
        return 1
    fi

    return 0
}

validate_nginx_config_files() {
    local nginx_dir="nginx"
    
    if [ ! -d "$nginx_dir" ]; then
        log_warn "Nginx配置目录不存在"
        return 1
    fi

    if [ ! -f "$nginx_dir/nginx-http.conf" ]; then
        log_warn "Nginx HTTP配置文件不存在"
        return 1
    fi

    if [ ! -f "$nginx_dir/nginx-https.conf" ]; then
        log_warn "Nginx HTTPS配置文件不存在"
        return 1
    fi

    if command -v nginx &>/dev/null; then
        if ! nginx -t -c "$PWD/$nginx_dir/nginx-http.conf" &>/dev/null; then
            log_warn "Nginx HTTP配置语法错误"
            return 1
        fi
        
        if ! nginx -t -c "$PWD/$nginx_dir/nginx-https.conf" &>/dev/null; then
            log_warn "Nginx HTTPS配置语法错误"
            return 1
        fi
    fi

    return 0
}

backup_existing_configuration() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="config.backup.$timestamp"

    if [ -f ".env" ] || [ -d "nginx" ]; then
        log_info "备份现有配置到: $backup_dir"
        mkdir -p "$backup_dir"

        if [ -f ".env" ]; then
            cp ".env" "$backup_dir/env.backup"
            log_info "已备份: .env"
        fi

        if [ -d "nginx" ]; then
            cp -r "nginx" "$backup_dir/"
            log_info "已备份: nginx/"
        fi

        log_success "配置备份完成"
    fi
}

create_env_configuration() {
    log_info "创建.env配置文件..."

    ensure_required_variables

    case $DB_TYPE in
        "local")
            create_local_env_config
            ;;
        "vercel")
            create_vercel_env_config
            ;;
        "custom")
            create_custom_env_config
            ;;
        *)
            log_error "未知的数据库类型: $DB_TYPE"
            exit 1
            ;;
    esac

    chmod 600 .env
    log_success ".env文件创建完成"
}

ensure_required_variables() {
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
        log_info "自动生成JWT密钥: $JWT_SECRET"
    fi

    if [ -z "$APP_PORT" ]; then
        APP_PORT=9191
    fi

    if [ -z "$DOMAIN" ]; then
        DOMAIN="localhost"
        log_warn "域名未设置，使用默认值: $DOMAIN"
    fi
}

create_local_env_config() {
    cat > .env << EOF
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

BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_KEEP_DAYS=30

HEALTH_CHECK_ENABLED=true
METRICS_ENABLED=false
DEBUG_MODE=false

EOF
}

create_vercel_env_config() {
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

LOG_LEVEL=info
LOG_FILE=/opt/notes-backend/logs/app.log

CORS_ORIGINS=https://$DOMAIN,http://$DOMAIN
RATE_LIMIT=100
SESSION_TIMEOUT=7200

BACKUP_ENABLED=false
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_KEEP_DAYS=30

HEALTH_CHECK_ENABLED=true
METRICS_ENABLED=false
DEBUG_MODE=false

EOF
}

create_custom_env_config() {
    cat > .env << EOF
DB_MODE=custom
CUSTOM_DB_HOST=$CUSTOM_DB_HOST
CUSTOM_DB_PORT=$CUSTOM_DB_PORT
CUSTOM_DB_USER=$CUSTOM_DB_USER
CUSTOM_DB_PASSWORD=$CUSTOM_DB_PASSWORD
CUSTOM_DB_NAME=$CUSTOM_DB_NAME
CUSTOM_DB_SSLMODE=${CUSTOM_DB_SSLMODE:-require}

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

BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_KEEP_DAYS=30

HEALTH_CHECK_ENABLED=true
METRICS_ENABLED=false
DEBUG_MODE=false

EOF
}

create_nginx_configurations() {
    log_info "创建Nginx配置文件..."

    mkdir -p nginx

    if nginx_configs_need_update; then
        create_nginx_http_config
        create_nginx_https_config
        log_success "Nginx配置文件创建完成"
    else
        log_info "Nginx配置文件已是最新版本"
    fi
}

nginx_configs_need_update() {
    if [ ! -f "nginx/nginx-http.conf" ] || [ ! -f "nginx/nginx-https.conf" ]; then
        return 0  # 需要更新
    fi

    if ! grep -q "server_name $DOMAIN" "nginx/nginx-http.conf"; then
        log_info "检测到域名变化，需要更新Nginx配置"
        return 0  # 需要更新
    fi

    if ! grep -q ":$APP_PORT" "nginx/nginx-http.conf"; then
        log_info "检测到端口变化，需要更新Nginx配置"
        return 0  # 需要更新
    fi

    return 1  # 不需要更新
}

create_nginx_http_config() {
    cat > nginx/nginx-http.conf << EOF
events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" '
                    'rt=\$request_time uct="\$upstream_connect_time" '
                    'uht="\$upstream_header_time" urt="\$upstream_response_time"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    client_body_timeout 60s;
    client_header_timeout 60s;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
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
    
    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    server {
        listen 80;
        server_name $DOMAIN;
        
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        
        location /health {
            proxy_pass http://172.17.0.1:$APP_PORT/health;
            access_log off;
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            try_files \$uri =404;
        }
        
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt|woff|woff2|ttf|svg)$ {
            proxy_pass http://172.17.0.1:$APP_PORT;
            expires 1y;
            add_header Cache-Control "public, immutable";
            add_header X-Content-Type-Options nosniff;
        }
        
        location /api/ {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_http_version 1.1;
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
        }
        
        location /api/notes/*/attachments {
            proxy_pass http://172.17.0.1:$APP_PORT;
            proxy_http_version 1.1;
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            client_max_body_size 100M;
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
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
    }
}
EOF
}

create_nginx_https_config() {
    cat > nginx/nginx-https.conf << EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" '
                    'rt=\$request_time uct="\$upstream_connect_time" '
                    'uht="\$upstream_header_time" urt="\$upstream_response_time"';
    
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
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
        listen 443 ssl http2;
        server_name $DOMAIN;
        
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        ssl_session_tickets off;
        ssl_stapling on;
        ssl_stapling_verify on;
        
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'" always;
        
        location /health {
            proxy_pass http://172.17.0.1:$APP_PORT/health;
            access_log off;
        }
        
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt|woff|woff2|ttf|svg)$ {
            proxy_pass http://172.17.0.1:$APP_PORT;
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
        
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
    }
}
EOF
}

validate_configuration_files() {
    log_info "验证配置文件..."

    local validation_errors=()

    if [ ! -f ".env" ]; then
        validation_errors+=(".env文件不存在")
    else
        if ! source .env 2>/dev/null; then
            validation_errors+=(".env文件格式错误")
        fi
    fi

    if [ ! -f "nginx/nginx-http.conf" ]; then
        validation_errors+=("Nginx HTTP配置文件不存在")
    fi

    if [ ! -f "nginx/nginx-https.conf" ]; then
        validation_errors+=("Nginx HTTPS配置文件不存在")
    fi

    if [ ${#validation_errors[@]} -gt 0 ]; then
        log_error "配置文件验证失败："
        for error in "${validation_errors[@]}"; do
            echo -e "   ❌ $error"
        done
        exit 1
    fi

    log_success "配置文件验证通过"
}

set_configuration_permissions() {
    log_info "设置配置文件权限..."

    chmod 600 .env

    chmod 644 nginx/*.conf

    chmod 755 nginx

    log_success "配置文件权限设置完成"
}

show_configuration_summary() {
    source .env 2>/dev/null || return

    echo -e "\n${CYAN}=== 配置摘要 ===${NC}"
    echo -e "数据库模式: ${GREEN}$DB_MODE${NC}"
    
    case "$DB_MODE" in
        "local")
            echo -e "数据库信息: ${GREEN}$LOCAL_DB_USER@localhost:5432/$LOCAL_DB_NAME${NC}"
            ;;
        "vercel")
            echo -e "数据库信息: ${GREEN}Vercel Postgres (云数据库)${NC}"
            ;;
        "custom")
            echo -e "数据库信息: ${GREEN}$CUSTOM_DB_USER@$CUSTOM_DB_HOST:$CUSTOM_DB_PORT/$CUSTOM_DB_NAME${NC}"
            ;;
    esac
    
    echo -e "应用端口: ${GREEN}$SERVER_PORT${NC}"
    echo -e "前端地址: ${GREEN}$FRONTEND_BASE_URL${NC}"
    echo -e "JWT密钥: ${GREEN}${JWT_SECRET:0:16}...${NC}"
    echo -e "上传目录: ${GREEN}$UPLOAD_PATH${NC}"
    echo -e "日志文件: ${GREEN}$LOG_FILE${NC}"
    
    echo -e "\n${CYAN}配置文件位置：${NC}"
    echo -e "  .env: ${GREEN}$PROJECT_DIR/.env${NC}"
    echo -e "  Nginx HTTP: ${GREEN}$PROJECT_DIR/nginx/nginx-http.conf${NC}"
    echo -e "  Nginx HTTPS: ${GREEN}$PROJECT_DIR/nginx/nginx-https.conf${NC}"
}

start_services() {
    if [ "$SERVICES_RUNNING" = true ] && [ "$SERVICES_HEALTHY" = true ]; then
        log_success "服务已运行且健康，跳过启动步骤"
        show_service_status
        return 0
    fi

    log_step "启动应用服务"

    ensure_database_ready

    start_application_service

    start_proxy_service

    verify_services_health

    log_success "所有服务启动完成"
    show_service_status
}

ensure_database_ready() {
    if [ "$DB_TYPE" = "local" ]; then
        log_info "确保本地数据库就绪..."
        
        if ! docker ps | grep -q "notes-postgres"; then
            log_info "启动数据库容器..."
            cd $PROJECT_DIR
            docker compose -f docker-compose.db.yml up -d
        fi
        
        wait_for_database_ready_startup
    else
        log_info "使用外部数据库，跳过数据库检查"
    fi
}

wait_for_database_ready_startup() {
    log_info "等待数据库完全就绪..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec notes-postgres pg_isready -U $DB_USER -d $DB_NAME &>/dev/null; then
            log_success "数据库就绪 (耗时: ${attempt}0秒)"
            sleep 5
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "数据库启动超时"
            show_database_troubleshooting_startup
            exit 1
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log_info "等待数据库就绪... (${attempt}/${max_attempts})"
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
}

start_application_service() {
    if systemctl is-active --quiet notes-backend; then
        log_info "应用服务已运行，检查健康状态..."
        
        if test_application_health; then
            log_success "应用服务运行正常"
            return 0
        else
            log_warn "应用服务运行但健康检查失败，重启服务..."
            restart_application_service
            return 0
        fi
    fi

    log_info "启动 Notes Backend 应用..."
    
    cd $PROJECT_DIR
    if [ ! -f "notes-backend" ] || [ ! -x "notes-backend" ]; then
        log_error "应用二进制文件不存在或不可执行"
        exit 1
    fi

    if [ ! -f ".env" ]; then
        log_error "配置文件不存在"
        exit 1
    fi

    if systemctl start notes-backend; then
        log_success "应用服务启动命令执行成功"
    else
        log_error "应用服务启动失败"
        show_application_troubleshooting
        exit 1
    fi

    wait_for_application_ready
}

restart_application_service() {
    log_info "重启应用服务..."
    
    systemctl restart notes-backend
    wait_for_application_ready
}

wait_for_application_ready() {
    log_info "等待应用启动..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet notes-backend; then
            if netstat -tlnp | grep -q ":$APP_PORT "; then
                if test_application_health; then
                    log_success "应用启动成功 (耗时: ${attempt}0秒)"
                    return 0
                fi
            fi
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "应用启动超时"
            show_application_startup_troubleshooting
            exit 1
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log_info "等待应用启动... (${attempt}/${max_attempts})"
            
            if ! systemctl is-active --quiet notes-backend; then
                log_warn "应用服务未运行，查看状态..."
                systemctl status notes-backend --no-pager -l | head -10
            fi
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
}

test_application_health() {
    if curl -f -s --connect-timeout 5 --max-time 10 "http://127.0.0.1:$APP_PORT/health" >/dev/null; then
        return 0
    fi
    
    return 1
}

start_proxy_service() {
    log_info "启动代理服务..."

    handle_service_conflicts

    local ssl_available=false
    if check_ssl_certificate_validity; then
        ssl_available=true
        log_info "检测到有效SSL证书，启动HTTPS服务"
        start_https_proxy
    else
        log_info "未检测到有效SSL证书，启动HTTP服务"
        start_http_proxy
    fi
}

check_ssl_certificate_validity() {
    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        return 1
    fi
    
    if openssl x509 -in "$cert_path" -text -noout 2>/dev/null | grep -qi "let's encrypt"; then
        if openssl x509 -in "$cert_path" -checkend 86400 >/dev/null 2>&1; then
            return 0  # 证书有效且未过期
        fi
    fi
    
    if openssl x509 -in "$cert_path" -text -noout >/dev/null 2>&1; then
        local issuer=$(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | grep -o "CN=[^,]*" | cut -d'=' -f2)
        if [ "$issuer" != "$DOMAIN" ]; then  # 不是自签名证书
            if openssl x509 -in "$cert_path" -checkend 86400 >/dev/null 2>&1; then
                return 0  # 第三方有效证书
            fi
        fi
    fi
    
    return 1
}

handle_service_conflicts() {
    log_info "处理服务冲突..."
    
    local conflicting_services=("nginx" "httpd" "apache2")
    
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "停止冲突服务: $service"
            systemctl stop "$service"
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
    
    systemctl stop notes-nginx-https 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    
    docker stop notes-nginx 2>/dev/null || true
    docker rm notes-nginx 2>/dev/null || true
    
    sleep 3
    
    check_and_clear_port_conflicts
}

check_and_clear_port_conflicts() {
    local ports_to_check=("80" "443")
    
    for port in "${ports_to_check[@]}"; do
        if netstat -tlnp | grep -q ":$port "; then
            log_warn "端口 $port 被占用，尝试清理..."
            
            local pids=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
            
            for pid in $pids; do
                if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                    local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                    log_info "终止占用端口 $port 的进程: $pid ($process_name)"
                    kill -TERM "$pid" 2>/dev/null || true
                fi
            done
            
            sleep 3
            
            if netstat -tlnp | grep -q ":$port "; then
                pids=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
                for pid in $pids; do
                    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                        log_warn "强制终止进程: $pid"
                        kill -KILL "$pid" 2>/dev/null || true
                    fi
                done
                sleep 2
            fi
        fi
    done
}

start_https_proxy() {
    log_info "启动HTTPS代理服务..."
    
    systemctl enable notes-nginx-https
    systemctl disable notes-nginx-http 2>/dev/null || true
    
    if systemctl start notes-nginx-https; then
        log_success "HTTPS代理启动命令执行成功"
    else
        log_error "HTTPS代理启动失败"
        show_nginx_troubleshooting
        exit 1
    fi
    
    wait_for_proxy_ready "https"
}

start_http_proxy() {
    log_info "启动HTTP代理服务..."
    
    systemctl enable notes-nginx-http
    systemctl disable notes-nginx-https 2>/dev/null || true
    
    if systemctl start notes-nginx-http; then
        log_success "HTTP代理启动命令执行成功"
    else
        log_error "HTTP代理启动失败"
        show_nginx_troubleshooting
        exit 1
    fi
    
    wait_for_proxy_ready "http"
}

wait_for_proxy_ready() {
    local proxy_type="$1"
    local service_name="notes-nginx-$proxy_type"
    
    log_info "等待${proxy_type^^}代理就绪..."
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet "$service_name"; then
            if docker ps | grep -q "notes-nginx"; then
                if test_proxy_health "$proxy_type"; then
                    log_success "${proxy_type^^}代理启动成功"
                    return 0
                fi
            fi
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "${proxy_type^^}代理启动超时"
            show_proxy_troubleshooting "$proxy_type"
            exit 1
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log_info "等待${proxy_type^^}代理启动... (${attempt}/${max_attempts})"
        fi
        
        sleep 5
        attempt=$((attempt + 1))
    done
}

test_proxy_health() {
    local proxy_type="$1"
    
    case "$proxy_type" in
        "http")
            curl -f -s --connect-timeout 5 --max-time 10 "http://127.0.0.1/health" >/dev/null
            ;;
        "https")
            curl -f -s -k --connect-timeout 5 --max-time 10 "https://127.0.0.1/health" >/dev/null
            ;;
    esac
}

verify_services_health() {
    log_info "验证服务健康状态..."
    
    local health_issues=()
    
    if ! systemctl is-active --quiet notes-backend; then
        health_issues+=("应用服务未运行")
    elif ! test_application_health; then
        health_issues+=("应用健康检查失败")
    fi
    
    if systemctl is-active --quiet notes-nginx-https; then
        if ! test_proxy_health "https"; then
            health_issues+=("HTTPS代理访问异常")
        fi
    elif systemctl is-active --quiet notes-nginx-http; then
        if ! test_proxy_health "http"; then
            health_issues+=("HTTP代理访问异常")
        fi
    else
        health_issues+=("代理服务未运行")
    fi
    
    if ! netstat -tlnp | grep -q ":$APP_PORT "; then
        health_issues+=("应用端口未监听")
    fi
    
    if ! netstat -tlnp | grep -q ":80 "; then
        health_issues+=("HTTP端口未监听")
    fi
    
    if [ ${#health_issues[@]} -eq 0 ]; then
        log_success "✅ 所有服务健康检查通过"
        SERVICES_HEALTHY=true
    else
        log_warn "⚠️ 发现以下健康问题："
        for issue in "${health_issues[@]}"; do
            echo -e "   ❌ $issue"
        done
        SERVICES_HEALTHY=false
    fi
}

show_service_status() {
    echo -e "\n${CYAN}=== 服务状态 ===${NC}"
    
    if systemctl is-active --quiet notes-backend; then
        echo -e "应用服务: ${GREEN}✅ 运行中${NC}"
        
        if test_application_health; then
            echo -e "应用健康: ${GREEN}✅ 正常${NC}"
        else
            echo -e "应用健康: ${YELLOW}⚠️ 异常${NC}"
        fi
    else
        echo -e "应用服务: ${RED}❌ 未运行${NC}"
    fi
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "代理服务: ${GREEN}✅ HTTPS模式${NC}"
        local access_url="https://$DOMAIN"
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "代理服务: ${GREEN}✅ HTTP模式${NC}"
        local access_url="http://$DOMAIN"
    else
        echo -e "代理服务: ${RED}❌ 未运行${NC}"
        local access_url="http://127.0.0.1:$APP_PORT"
    fi
    
    echo -e "\n${CYAN}端口监听状态：${NC}"
    if netstat -tlnp | grep -q ":$APP_PORT "; then
        echo -e "应用端口 $APP_PORT: ${GREEN}✅ 监听中${NC}"
    else
        echo -e "应用端口 $APP_PORT: ${RED}❌ 未监听${NC}"
    fi
    
    if netstat -tlnp | grep -q ":80 "; then
        echo -e "HTTP端口 80: ${GREEN}✅ 监听中${NC}"
    else
        echo -e "HTTP端口 80: ${RED}❌ 未监听${NC}"
    fi
    
    if netstat -tlnp | grep -q ":443 "; then
        echo -e "HTTPS端口 443: ${GREEN}✅ 监听中${NC}"
    else
        echo -e "HTTPS端口 443: ${YELLOW}⚠️ 未监听${NC}"
    fi
    
    echo -e "\n${CYAN}访问地址：${NC}"
    echo -e "主要访问: ${GREEN}$access_url${NC}"
    echo -e "健康检查: ${GREEN}$access_url/health${NC}"
    echo -e "API基址: ${GREEN}$access_url/api${NC}"
}

show_application_troubleshooting() {
    echo -e "\n${YELLOW}应用服务故障排除：${NC}"
    echo -e "1. 查看服务状态：systemctl status notes-backend"
    echo -e "2. 查看应用日志：journalctl -u notes-backend -f"
    echo -e "3. 检查配置文件：cat $PROJECT_DIR/.env"
    echo -e "4. 检查二进制文件：ls -la $PROJECT_DIR/notes-backend"
    echo -e "5. 测试直接运行：cd $PROJECT_DIR && ./notes-backend"
}

show_application_startup_troubleshooting() {
    echo -e "\n${YELLOW}应用启动故障排除：${NC}"
    
    echo -e "\n${CYAN}服务状态：${NC}"
    systemctl status notes-backend --no-pager -l | head -15
    
    echo -e "\n${CYAN}最近日志：${NC}"
    journalctl -u notes-backend -n 20 --no-pager
    
    echo -e "\n${CYAN}端口检查：${NC}"
    netstat -tlnp | grep -E ":$APP_PORT|:80|:443" || echo "无相关端口监听"
}

show_nginx_troubleshooting() {
    echo -e "\n${YELLOW}Nginx代理故障排除：${NC}"
    echo -e "1. 查看Docker状态：docker ps -a | grep nginx"
    echo -e "2. 查看容器日志：docker logs notes-nginx"
    echo -e "3. 检查配置文件：docker exec notes-nginx nginx -t"
    echo -e "4. 重启代理服务：systemctl restart notes-nginx-http"
}

show_proxy_troubleshooting() {
    local proxy_type="$1"
    
    echo -e "\n${YELLOW}${proxy_type^^}代理故障排除：${NC}"
    
    echo -e "\n${CYAN}服务状态：${NC}"
    systemctl status "notes-nginx-$proxy_type" --no-pager -l | head -10
    
    echo -e "\n${CYAN}容器状态：${NC}"
    docker ps -a | grep nginx || echo "未找到nginx容器"
    
    echo -e "\n${CYAN}容器日志：${NC}"
    docker logs notes-nginx --tail 20 2>/dev/null || echo "无法获取容器日志"
}

show_database_troubleshooting_startup() {
    echo -e "\n${YELLOW}数据库启动故障排除：${NC}"
    echo -e "1. 查看容器状态：docker ps -a | grep postgres"
    echo -e "2. 查看容器日志：docker logs notes-postgres"
    echo -e "3. 重启数据库：docker restart notes-postgres"
    echo -e "4. 重新创建：cd $PROJECT_DIR && docker compose -f docker-compose.db.yml down && docker compose -f docker-compose.db.yml up -d"
}

main() {
    trap cleanup_on_error ERR
    set -e

    initialize_global_variables

    show_welcome

    check_root

    if perform_quick_health_check; then
        handle_existing_deployment
        return 0
    fi

    collect_user_input
    collect_database_config

    detect_system
    optimize_network

    install_components_as_needed

    prepare_project_and_compile

    setup_database_and_configuration

    create_and_start_services

    configure_https_if_needed

    final_verification_and_display

    log_success "部署流程完成！"
}

initialize_global_variables() {
    PROJECT_NAME="notes-backend"
    PROJECT_DIR="/opt/$PROJECT_NAME"
    APP_PORT=9191
    DEFAULT_DOMAIN="huage.api.withgo.cn"
    DEFAULT_EMAIL="23200804@qq.com"
    DEFAULT_REPO="https://github.com/wurslu/huage"

    BASIC_TOOLS_INSTALLED=false
    GO_INSTALLED=false
    DOCKER_INSTALLED=false
    CERTBOT_INSTALLED=false
    PROJECT_EXISTS=false
    CONFIG_EXISTS=false
    SERVICES_RUNNING=false
    SERVICES_HEALTHY=false
    LOCAL_DB_RUNNING=false
    FIREWALL_CONFIGURED=false
}

perform_quick_health_check() {
    log_info "执行快速系统健康检查..."

    if systemctl is-active --quiet notes-backend; then
        if systemctl is-active --quiet notes-nginx-https || systemctl is-active --quiet notes-nginx-http; then
            if curl -f -s --connect-timeout 3 "http://127.0.0.1:9191/health" >/dev/null 2>&1; then
                log_success "检测到系统已部署且运行正常"
                return 0
            fi
        fi
    fi

    return 1
}

handle_existing_deployment() {
    echo -e "\n${GREEN}🎉 系统已完全部署且运行正常！${NC}"
    echo -e "\n${CYAN}请选择操作：${NC}"
    echo -e "${YELLOW}1.${NC} 查看系统状态"
    echo -e "${YELLOW}2.${NC} 重启所有服务"
    echo -e "${YELLOW}3.${NC} 更新应用代码"
    echo -e "${YELLOW}4.${NC} 配置HTTPS"
    echo -e "${YELLOW}5.${NC} 完整重新部署"
    echo -e "${YELLOW}6.${NC} 退出"
    echo -e ""
    read -p "请选择 (1-6): " choice

    case $choice in
        1)
            show_system_status_detailed
            ;;
        2)
            restart_all_services
            ;;
        3)
            update_application_code
            ;;
        4)
            configure_https_standalone
            ;;
        5)
            log_info "执行完整重新部署..."
            return 1  # 继续执行完整部署流程
            ;;
        6)
            log_info "退出脚本"
            exit 0
            ;;
        *)
            log_warn "无效选择，显示系统状态"
            show_system_status_detailed
            ;;
    esac
}

show_system_status_detailed() {
    echo -e "\n${CYAN}=== 详细系统状态 ===${NC}"
    
    echo -e "\n${CYAN}🔧 服务状态：${NC}"
    systemctl status notes-backend --no-pager -l | head -5
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "代理模式: ${GREEN}HTTPS${NC}"
        systemctl status notes-nginx-https --no-pager -l | head -3
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "代理模式: ${GREEN}HTTP${NC}"
        systemctl status notes-nginx-http --no-pager -l | head -3
    fi
    
    echo -e "\n${CYAN}🔌 端口监听：${NC}"
    netstat -tlnp | grep -E ":80|:443|:9191" | while read line; do
        echo -e "  $line"
    done
    
    echo -e "\n${CYAN}💚 健康检查：${NC}"
    if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
        echo -e "  应用健康: ${GREEN}✅ 正常${NC}"
    else
        echo -e "  应用健康: ${RED}❌ 异常${NC}"
    fi
    
    echo -e "\n${CYAN}📊 系统资源：${NC}"
    echo -e "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo -e "  内存: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
    echo -e "  磁盘: $(df -h $PROJECT_DIR | awk 'NR==2{print $5}')"
    
    echo -e "\n${CYAN}🌐 访问信息：${NC}"
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "  主站: ${GREEN}https://$DEFAULT_DOMAIN${NC}"
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "  主站: ${GREEN}http://$DEFAULT_DOMAIN${NC}"
    fi
    echo -e "  健康检查: ${GREEN}http://127.0.0.1:9191/health${NC}"
}

restart_all_services() {
    log_info "重启所有服务..."
    
    echo -e "${CYAN}停止服务...${NC}"
    systemctl stop notes-nginx-https 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl stop notes-backend
    
    echo -e "${CYAN}启动服务...${NC}"
    systemctl start notes-backend
    sleep 5
    
    if systemctl is-enabled notes-nginx-https 2>/dev/null; then
        systemctl start notes-nginx-https
        echo -e "${GREEN}✅ 服务已重启 (HTTPS模式)${NC}"
    else
        systemctl start notes-nginx-http
        echo -e "${GREEN}✅ 服务已重启 (HTTP模式)${NC}"
    fi
    
    sleep 5
    if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
        echo -e "${GREEN}🎉 服务重启成功且健康检查通过${NC}"
    else
        echo -e "${YELLOW}⚠️ 服务已重启但健康检查失败${NC}"
    fi
}

update_application_code() {
    log_info "更新应用代码..."
    
    cd $PROJECT_DIR
    
    if [ -d ".git" ]; then
        echo -e "${CYAN}更新代码...${NC}"
        git fetch origin
        git pull origin main || git pull origin master
        
        echo -e "${CYAN}重新编译...${NC}"
        export PATH=$PATH:/usr/local/go/bin
        if go build -ldflags="-w -s" -o notes-backend cmd/server/main.go; then
            echo -e "${GREEN}✅ 编译成功${NC}"
            
            echo -e "${CYAN}重启应用...${NC}"
            systemctl restart notes-backend
            sleep 5
            
            if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
                echo -e "${GREEN}🎉 应用更新成功${NC}"
            else
                echo -e "${YELLOW}⚠️ 应用更新后健康检查失败${NC}"
            fi
        else
            echo -e "${RED}❌ 编译失败${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ 非Git仓库，无法自动更新${NC}"
    fi
}

configure_https_standalone() {
    log_info "配置HTTPS..."
    
    if [ -f "$PROJECT_DIR/enable-https.sh" ]; then
        cd $PROJECT_DIR
        bash enable-https.sh
    else
        echo -e "${YELLOW}⚠️ enable-https.sh 脚本不存在${NC}"
        echo -e "请运行完整部署后再配置HTTPS"
    fi
}

install_components_as_needed() {
    log_step "检查和安装必需组件"

    if [ "$BASIC_TOOLS_INSTALLED" != true ]; then
        install_basic_tools
    else
        log_success "✅ 基础工具已安装"
    fi

    if [ "$GO_INSTALLED" != true ]; then
        install_go
    else
        log_success "✅ Go语言环境已安装"
    fi

    if [ "$DOCKER_INSTALLED" != true ]; then
        install_docker
    else
        log_success "✅ Docker已安装"
    fi

    if [ "$CERTBOT_INSTALLED" != true ]; then
        install_certbot
    else
        log_success "✅ Certbot已安装"
    fi

    if [ "$FIREWALL_CONFIGURED" != true ]; then
        setup_firewall
    else
        log_success "✅ 防火墙已配置"
    fi
}

prepare_project_and_compile() {
    log_step "准备项目代码和编译"

    if [ "$PROJECT_EXISTS" != true ]; then
        clone_project
    else
        log_success "✅ 项目代码已存在"
    fi

    compile_application
}

setup_database_and_configuration() {
    log_step "配置数据库和环境"

    setup_database

    if [ "$CONFIG_EXISTS" != true ] || ! validate_existing_configuration; then
        create_configuration
    else
        log_success "✅ 配置文件已存在且有效"
    fi
}

create_and_start_services() {
    log_step "创建和启动服务"

    create_system_services

    handle_conflicts

    start_services

    create_management_scripts
}

configure_https_if_needed() {
    if setup_https_option; then
        log_success "✅ HTTPS配置完成"
    else
        log_info "ℹ️ HTTPS配置已跳过，可稍后手动配置"
    fi
}

final_verification_and_display() {
    log_step "最终验证和结果展示"

    verify_deployment

    show_final_result
}

cleanup_on_error() {
    local exit_code=$?
    
    log_error "部署过程中出现错误 (退出码: $exit_code)"
    
    echo -e "\n${YELLOW}🔍 错误诊断信息：${NC}"
    
    if [ -f "/var/log/messages" ]; then
        echo -e "\n${CYAN}系统日志 (最近10行)：${NC}"
        tail -10 /var/log/messages 2>/dev/null || true
    fi
    
    echo -e "\n${CYAN}服务状态：${NC}"
    systemctl status notes-backend --no-pager -l 2>/dev/null | head -5 || true
    
    echo -e "\n${CYAN}Docker状态：${NC}"
    docker ps -a | grep -E "notes|postgres" || echo "无相关容器"
    
    echo -e "\n${CYAN}端口占用：${NC}"
    netstat -tlnp | grep -E ":80|:443|:9191" || echo "无相关端口监听"
    
    echo -e "\n${YELLOW}📋 故障排除建议：${NC}"
    echo -e "1. 查看详细错误：journalctl -u notes-backend -n 50"
    echo -e "2. 检查网络连接：ping -c 3 8.8.8.8"
    echo -e "3. 检查磁盘空间：df -h"
    echo -e "4. 重新运行脚本：bash $0"
    echo -e "5. 手动清理后重试：systemctl stop notes-* && docker system prune -f"
    
    save_error_logs
    
    exit $exit_code
}

save_error_logs() {
    local log_dir="/opt/notes-backend-debug"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local error_log="$log_dir/error_$timestamp.log"
    
    mkdir -p "$log_dir"
    
    echo "=== Notes Backend 部署错误日志 ===" > "$error_log"
    echo "时间: $(date)" >> "$error_log"
    echo "脚本版本: $(head -5 $0 | tail -1)" >> "$error_log"
    echo "" >> "$error_log"
    
    echo "=== 系统信息 ===" >> "$error_log"
    uname -a >> "$error_log" 2>&1
    cat /etc/os-release >> "$error_log" 2>&1
    echo "" >> "$error_log"
    
    echo "=== 服务状态 ===" >> "$error_log"
    systemctl status notes-backend >> "$error_log" 2>&1
    echo "" >> "$error_log"
    
    echo "=== Docker状态 ===" >> "$error_log"
    docker ps -a >> "$error_log" 2>&1
    echo "" >> "$error_log"
    
    echo "=== 最近日志 ===" >> "$error_log"
    journalctl -u notes-backend -n 50 >> "$error_log" 2>&1
    
    log_info "错误日志已保存到: $error_log"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

setup_https_option() {
    log_step "HTTPS配置选项"

    if ! command -v certbot &>/dev/null; then
        log_warn "Certbot未安装，跳过HTTPS配置"
        return 1
    fi

    log_info "检查域名解析..."
    if ! check_domain_resolution "$DOMAIN"; then
        log_warn "域名解析未配置或未生效，跳过HTTPS配置"
        show_domain_setup_guide
        return 1
    fi

    echo -e "\n${CYAN}是否现在配置HTTPS？ (y/N):${NC}"
    echo -e "${YELLOW}注意：需要确保域名已正确解析到此服务器${NC}"
    read -p "> " SETUP_HTTPS

    if [[ "$SETUP_HTTPS" =~ ^[Yy]$ ]]; then
        if setup_ssl_certificate_optimized; then
            log_success "HTTPS证书配置成功"
            switch_to_https_mode
            return 0
        else
            log_warn "HTTPS证书配置失败，继续使用HTTP模式"
            return 1
        fi
    else
        log_info "跳过HTTPS配置，可稍后运行 ./enable-https.sh 启用"
        return 1
    fi
}

check_domain_resolution() {
    local domain="$1"
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    
    if [ -z "$server_ip" ]; then
        log_warn "无法获取服务器公网IP"
        return 1
    fi
    
    local dns_servers=("8.8.8.8" "1.1.1.1" "114.114.114.114")
    local resolved_ip=""
    
    for dns in "${dns_servers[@]}"; do
        resolved_ip=$(nslookup "$domain" "$dns" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")
        if [ -n "$resolved_ip" ] && [ "$resolved_ip" = "$server_ip" ]; then
            log_success "域名解析验证通过: $domain -> $server_ip"
            return 0
        fi
    done
    
    log_warn "域名解析验证失败"
    log_info "  域名: $domain"
    log_info "  服务器IP: $server_ip"
    log_info "  解析IP: $resolved_ip"
    
    return 1
}

show_domain_setup_guide() {
    echo -e "\n${YELLOW}📋 域名配置指南：${NC}"
    echo -e "\n${CYAN}1. 获取服务器IP地址：${NC}"
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "请手动获取")
    echo -e "   服务器IP: ${GREEN}$server_ip${NC}"
    
    echo -e "\n${CYAN}2. 在域名服务商设置DNS记录：${NC}"
    echo -e "   记录类型: ${YELLOW}A${NC}"
    echo -e "   主机记录: ${YELLOW}@${NC} (或留空)"
    echo -e "   记录值: ${YELLOW}$server_ip${NC}"
    echo -e "   TTL: ${YELLOW}600${NC} (10分钟)"
    
    echo -e "\n${CYAN}3. 验证域名解析：${NC}"
    echo -e "   命令: ${YELLOW}nslookup $DOMAIN 8.8.8.8${NC}"
    echo -e "   期望结果: ${YELLOW}$server_ip${NC}"
    
    echo -e "\n${CYAN}4. 等待DNS传播（通常5-30分钟）${NC}"
    echo -e "\n${CYAN}5. 域名生效后运行：${YELLOW}./enable-https.sh${NC}"
}

setup_ssl_certificate_optimized() {
    log_info "获取SSL证书..."
    
    prepare_port_80_for_certbot
    
    cleanup_existing_certificates
    
    if request_letsencrypt_certificate; then
        setup_certificate_renewal
        return 0
    else
        return 1
    fi
}

prepare_port_80_for_certbot() {
    log_info "准备端口80用于证书验证..."
    
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl stop notes-nginx-https 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    
    docker stop notes-nginx 2>/dev/null || true
    
    sleep 3
    
    if netstat -tlnp | grep -q ":80 "; then
        log_warn "端口80仍被占用，强制清理..."
        local pids=$(netstat -tlnp | grep ":80 " | awk '{print $7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
        for pid in $pids; do
            if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 2
    fi
    
    if netstat -tlnp | grep -q ":80 "; then
        log_error "无法清理端口80，证书申请可能失败"
        return 1
    fi
    
    log_success "端口80已准备就绪"
}

cleanup_existing_certificates() {
    log_info "清理现有证书配置..."
    
    certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
    rm -rf "/etc/letsencrypt/live/$DOMAIN"
    rm -rf "/etc/letsencrypt/archive/$DOMAIN"
    rm -rf "/etc/letsencrypt/renewal/$DOMAIN.conf"
    
    log_info "证书清理完成"
}

request_letsencrypt_certificate() {
    log_info "申请Let's Encrypt SSL证书..."
    
    if certbot certonly \
        --standalone \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN" \
        --non-interactive \
        --force-renewal \
        --verbose; then
        
        log_success "SSL证书申请成功"
        
        if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && \
           [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
            
            local expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate | cut -d= -f2)
            log_info "证书有效期至: $expiry_date"
            
            return 0
        else
            log_error "证书文件验证失败"
            return 1
        fi
    else
        log_error "SSL证书申请失败"
        show_ssl_troubleshooting
        return 1
    fi
}

setup_certificate_renewal() {
    log_info "配置证书自动续期..."
    
    cat > /usr/local/bin/renew-ssl-certificates.sh << 'EOF'

LOG_FILE="/var/log/ssl-renewal.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] 开始检查SSL证书续期" >> "$LOG_FILE"

systemctl stop notes-nginx-https 2>/dev/null || systemctl stop notes-nginx-http 2>/dev/null

if certbot renew --quiet --force-renewal; then
    echo "[$DATE] SSL证书续期成功" >> "$LOG_FILE"
    
    if systemctl is-enabled notes-nginx-https &>/dev/null; then
        systemctl start notes-nginx-https
        echo "[$DATE] HTTPS服务重启完成" >> "$LOG_FILE"
    else
        systemctl start notes-nginx-http
        echo "[$DATE] HTTP服务重启完成" >> "$LOG_FILE"
    fi
else
    echo "[$DATE] SSL证书续期失败" >> "$LOG_FILE"
    
    if systemctl is-enabled notes-nginx-https &>/dev/null; then
        systemctl start notes-nginx-https
    else
        systemctl start notes-nginx-http
    fi
fi

echo "[$DATE] 证书续期流程完成" >> "$LOG_FILE"
EOF

    chmod +x /usr/local/bin/renew-ssl-certificates.sh

    (
        crontab -l 2>/dev/null | grep -v "renew-ssl-certificates"
        echo "0 3 * * * /usr/local/bin/renew-ssl-certificates.sh"
    ) | crontab -

    log_success "证书自动续期配置完成"
}

switch_to_https_mode() {
    log_info "切换到HTTPS模式..."
    
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl disable notes-nginx-http 2>/dev/null || true
    
    systemctl enable notes-nginx-https
    systemctl start notes-nginx-https
    
    sleep 5
    
    if systemctl is-active --quiet notes-nginx-https; then
        log_success "HTTPS模式启动成功"
        
        if curl -f -k -s "https://127.0.0.1/health" >/dev/null; then
            log_success "HTTPS访问测试通过"
        else
            log_warn "HTTPS访问测试失败，但服务已启动"
        fi
    else
        log_error "HTTPS模式启动失败"
        return 1
    fi
}

show_ssl_troubleshooting() {
    echo -e "\n${YELLOW}SSL证书申请故障排除：${NC}"
    echo -e "1. 检查域名解析：nslookup $DOMAIN 8.8.8.8"
    echo -e "2. 检查防火墙：firewall-cmd --list-ports"
    echo -e "3. 检查安全组：确保80、443端口开放"
    echo -e "4. 检查端口占用：netstat -tlnp | grep :80"
    echo -e "5. 手动测试：certbot certonly --standalone -d $DOMAIN"
    
    echo -e "\n${YELLOW}常见问题：${NC}"
    echo -e "• 域名解析未生效（需等待DNS传播）"
    echo -e "• 云服务器安全组未开放80端口"
    echo -e "• 防火墙阻止了80端口访问"
    echo -e "• 域名已有其他证书服务商的证书"
}

create_system_services() {
    log_step "创建系统服务"
    
    if check_existing_services; then
        log_success "系统服务已存在且配置正确"
        return 0
    fi
    
    log_info "创建系统服务配置..."
    
    create_notes_backend_service
    create_nginx_http_service
    create_nginx_https_service
    
    systemctl daemon-reload
    systemctl enable notes-backend
    
    log_success "系统服务创建完成"
}

check_existing_services() {
    local services=("notes-backend" "notes-nginx-http" "notes-nginx-https")
    
    for service in "${services[@]}"; do
        if [ ! -f "/etc/systemd/system/$service.service" ]; then
            return 1
        fi
        
        if ! grep -q "$PROJECT_DIR" "/etc/systemd/system/$service.service" 2>/dev/null; then
            return 1
        fi
    done
    
    return 0
}

create_notes_backend_service() {
    log_info "创建Notes Backend服务..."
    
    cat > /etc/systemd/system/notes-backend.service << EOF
[Unit]
Description=Notes Backend Application
Documentation=https://github.com/your-repo/notes-backend
After=network.target network-online.target
Wants=network-online.target
RequiresMountsFor=$PROJECT_DIR

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
Environment=PATH=/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/notes-backend
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -TERM \$MAINPID
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=5
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$PROJECT_DIR
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

    log_success "Notes Backend服务创建完成"
}

create_nginx_http_service() {
    log_info "创建Nginx HTTP服务..."
    
    cat > /etc/systemd/system/notes-nginx-http.service << EOF
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
    --health-cmd="nginx -t" \\
    --health-interval=30s \\
    --health-timeout=10s \\
    --health-retries=3 \\
    nginx:alpine

ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=-/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF

    log_success "Nginx HTTP服务创建完成"
}

create_nginx_https_service() {
    log_info "创建Nginx HTTPS服务..."
    
    cat > /etc/systemd/system/notes-nginx-https.service << EOF
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
    --health-cmd="nginx -t" \\
    --health-interval=30s \\
    --health-timeout=10s \\
    --health-retries=3 \\
    nginx:alpine

ExecStop=/usr/bin/docker stop notes-nginx
ExecStopPost=-/usr/bin/docker rm notes-nginx

[Install]
WantedBy=multi-user.target
EOF

    log_success "Nginx HTTPS服务创建完成"
}

handle_conflicts() {
    log_step "处理端口冲突和环境问题"

    if ! check_port_conflicts; then
        log_success "无端口冲突，跳过冲突处理"
        return 0
    fi

    log_info "检测到端口冲突，开始处理..."

    stop_conflicting_services

    cleanup_residual_processes

    restart_docker_service

    verify_conflicts_resolved

    log_success "环境冲突处理完成"
}

check_port_conflicts() {
    local conflicting_ports=("80" "443")
    local has_conflicts=false
    
    for port in "${conflicting_ports[@]}"; do
        if netstat -tlnp | grep -q ":$port "; then
            local process_info=$(netstat -tlnp | grep ":$port " | head -1)
            log_warn "端口 $port 被占用: $process_info"
            has_conflicts=true
        fi
    done
    
    return $has_conflicts
}

stop_conflicting_services() {
    log_info "停止可能冲突的服务..."
    
    local services=("nginx" "httpd" "apache2" "notes-nginx-http" "notes-nginx-https")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "停止服务: $service"
            systemctl stop "$service"
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
}

cleanup_residual_processes() {
    log_info "清理残留进程..."
    
    pkill -f nginx 2>/dev/null || true
    pkill -f httpd 2>/dev/null || true
    pkill -f apache 2>/dev/null || true
    
    docker stop notes-nginx 2>/dev/null || true
    docker rm notes-nginx 2>/dev/null || true
    
    sleep 3
}

restart_docker_service() {
    log_info "重启Docker服务..."
    systemctl restart docker
    sleep 5
    
    if systemctl is-active --quiet docker; then
        log_success "Docker服务重启成功"
    else
        log_error "Docker服务重启失败"
        exit 1
    fi
}

verify_conflicts_resolved() {
    log_info "验证冲突是否解决..."
    
    local still_conflicted=false
    
    if netstat -tlnp | grep -q ":80 "; then
        log_warn "端口80仍被占用："
        netstat -tlnp | grep ":80 "
        still_conflicted=true
    fi
    
    if netstat -tlnp | grep -q ":443 "; then
        log_warn "端口443仍被占用："
        netstat -tlnp | grep ":443 "
        still_conflicted=true
    fi
    
    if [ "$still_conflicted" = true ]; then
        log_error "仍存在端口冲突，请手动检查"
        exit 1
    fi
    
    log_success "所有端口冲突已解决"
}

force_clear_port() {
    local port="$1"
    
    log_info "强制清理端口 $port..."
    
    local pids=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
    
    for pid in $pids; do
        if [ -n "$pid" ] && [ "$pid" != "-" ]; then
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            log_info "终止进程: $pid ($process_name)"
            
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "强制终止进程: $pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
    done
    
    sleep 1
    
    if netstat -tlnp | grep -q ":$port "; then
        log_error "端口 $port 仍被占用，无法强制清理"
        return 1
    else
        log_success "端口 $port 已成功释放"
        return 0
    fi
}

check_port_status() {
    local port="$1"
    
    if netstat -tlnp | grep -q ":$port "; then
        local process_info=$(netstat -tlnp | grep ":$port " | head -1 | awk '{print $7}')
        echo "端口 $port 被占用: $process_info"
        return 0
    else
        echo "端口 $port 空闲"
        return 1
    fi
}

wait_for_port_free() {
    local port="$1"
    local timeout="${2:-30}"
    local count=0
    
    log_info "等待端口 $port 释放..."
    
    while [ $count -lt $timeout ]; do
        if ! netstat -tlnp | grep -q ":$port "; then
            log_success "端口 $port 已释放"
            return 0
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    log_error "等待端口 $port 释放超时"
    return 1
}

verify_deployment() {
    log_step "验证部署结果"

    local verification_passed=true
    local issues=()

    if ! systemctl is-active --quiet notes-backend; then
        issues+=("应用服务未运行")
        verification_passed=false
    fi

    if ! systemctl is-active --quiet notes-nginx-https && ! systemctl is-active --quiet notes-nginx-http; then
        issues+=("代理服务未运行")
        verification_passed=false
    fi

    if ! netstat -tlnp | grep -q ":$APP_PORT "; then
        issues+=("应用端口未监听")
        verification_passed=false
    fi

    if ! netstat -tlnp | grep -q ":80 "; then
        issues+=("HTTP端口未监听")
        verification_passed=false
    fi

    if ! test_application_health; then
        issues+=("应用健康检查失败")
        verification_passed=false
    fi

    local proxy_test_passed=false
    if systemctl is-active --quiet notes-nginx-https; then
        if curl -f -k -s "https://127.0.0.1/health" >/dev/null; then
            proxy_test_passed=true
        fi
    elif systemctl is-active --quiet notes-nginx-http; then
        if curl -f -s "http://127.0.0.1/health" >/dev/null; then
            proxy_test_passed=true
        fi
    fi

    if [ "$proxy_test_passed" = false ]; then
        issues+=("代理访问测试失败")
        verification_passed=false
    fi

    if [ "$verification_passed" = true ]; then
        log_success "✅ 部署验证完全通过"
    else
        log_warn "⚠️ 部署验证发现以下问题："
        for issue in "${issues[@]}"; do
            echo -e "   ❌ $issue"
        done
        
        echo -e "\n${YELLOW}建议操作：${NC}"
        echo -e "1. 查看服务状态：systemctl status notes-backend"
        echo -e "2. 查看应用日志：journalctl -u notes-backend -f"
        echo -e "3. 检查网络配置：netstat -tlnp | grep -E ':80|:443|:$APP_PORT'"
        echo -e "4. 重启服务：./restart.sh"
    fi

    return $verification_passed
}

show_system_status_detailed() {
    echo -e "\n${CYAN}=== 详细系统状态 ===${NC}"
    
    echo -e "\n${CYAN}🔧 服务状态：${NC}"
    systemctl status notes-backend --no-pager -l | head -5
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "代理模式: ${GREEN}HTTPS${NC}"
        systemctl status notes-nginx-https --no-pager -l | head -3
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "代理模式: ${GREEN}HTTP${NC}"
        systemctl status notes-nginx-http --no-pager -l | head -3
    fi
    
    echo -e "\n${CYAN}🔌 端口监听：${NC}"
    netstat -tlnp | grep -E ":80|:443|:9191" | while read line; do
        echo -e "  $line"
    done
    
    echo -e "\n${CYAN}💚 健康检查：${NC}"
    if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
        echo -e "  应用健康: ${GREEN}✅ 正常${NC}"
    else
        echo -e "  应用健康: ${RED}❌ 异常${NC}"
    fi
    
    echo -e "\n${CYAN}📊 系统资源：${NC}"
    echo -e "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo -e "  内存: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
    echo -e "  磁盘: $(df -h $PROJECT_DIR | awk 'NR==2{print $5}')"
    
    echo -e "\n${CYAN}🌐 访问信息：${NC}"
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "  主站: ${GREEN}https://$DEFAULT_DOMAIN${NC}"
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "  主站: ${GREEN}http://$DEFAULT_DOMAIN${NC}"
    fi
    echo -e "  健康检查: ${GREEN}http://127.0.0.1:9191/health${NC}"
}

restart_all_services() {
    log_info "重启所有服务..."
    
    echo -e "${CYAN}停止服务...${NC}"
    systemctl stop notes-nginx-https 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl stop notes-backend
    
    echo -e "${CYAN}启动服务...${NC}"
    systemctl start notes-backend
    sleep 5
    
    if systemctl is-enabled notes-nginx-https 2>/dev/null; then
        systemctl start notes-nginx-https
        echo -e "${GREEN}✅ 服务已重启 (HTTPS模式)${NC}"
    else
        systemctl start notes-nginx-http
        echo -e "${GREEN}✅ 服务已重启 (HTTP模式)${NC}"
    fi
    
    sleep 5
    if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
        echo -e "${GREEN}🎉 服务重启成功且健康检查通过${NC}"
    else
        echo -e "${YELLOW}⚠️ 服务已重启但健康检查失败${NC}"
    fi
}

update_application_code() {
    log_info "更新应用代码..."
    
    cd $PROJECT_DIR
    
    if [ -d ".git" ]; then
        echo -e "${CYAN}更新代码...${NC}"
        git fetch origin
        git pull origin main || git pull origin master
        
        echo -e "${CYAN}重新编译...${NC}"
        export PATH=$PATH:/usr/local/go/bin
        if go build -ldflags="-w -s" -o notes-backend cmd/server/main.go; then
            echo -e "${GREEN}✅ 编译成功${NC}"
            
            echo -e "${CYAN}重启应用...${NC}"
            systemctl restart notes-backend
            sleep 5
            
            if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
                echo -e "${GREEN}🎉 应用更新成功${NC}"
            else
                echo -e "${YELLOW}⚠️ 应用更新后健康检查失败${NC}"
            fi
        else
            echo -e "${RED}❌ 编译失败${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ 非Git仓库，无法自动更新${NC}"
    fi
}

configure_https_standalone() {
    log_info "配置HTTPS..."
    
    if [ -f "$PROJECT_DIR/enable-https.sh" ]; then
        cd $PROJECT_DIR
        bash enable-https.sh
    else
        echo -e "${YELLOW}⚠️ enable-https.sh 脚本不存在${NC}"
        echo -e "请运行完整部署后再配置HTTPS"
    fi
}

check_service_health() {
    local health_status="healthy"
    local issues=()
    
    if ! systemctl is-active --quiet notes-backend; then
        health_status="unhealthy"
        issues+=("应用服务未运行")
    elif ! test_application_health; then
        health_status="degraded"
        issues+=("应用健康检查失败")
    fi
    
    if ! systemctl is-active --quiet notes-nginx-https && ! systemctl is-active --quiet notes-nginx-http; then
        health_status="unhealthy"
        issues+=("代理服务未运行")
    fi
    
    case $health_status in
        "healthy")
            echo "healthy"
            return 0
            ;;
        "degraded")
            echo "degraded"
            return 1
            ;;
        "unhealthy")
            echo "unhealthy"
            return 2
            ;;
    esac
}

generate_health_report() {
    local report_file="/tmp/notes-backend-health-$(date +%Y%m%d_%H%M%S).txt"
    
    echo "Notes Backend 健康报告" > "$report_file"
    echo "生成时间: $(date)" >> "$report_file"
    echo "======================================" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "服务状态:" >> "$report_file"
    systemctl status notes-backend --no-pager >> "$report_file" 2>&1
    
    echo "" >> "$report_file"
    echo "端口监听:" >> "$report_file"
    netstat -tlnp | grep -E ":80|:443|:9191" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "系统资源:" >> "$report_file"
    free -h >> "$report_file"
    df -h >> "$report_file"
    
    echo "健康报告已生成: $report_file"
    return 0
}


test_network_connectivity() {
    log_info "测试网络连接..."
    
    local test_hosts=("8.8.8.8" "1.1.1.1" "github.com" "docker.io")
    local connectivity_score=0
    local total_tests=${#test_hosts[@]}
    
    for host in "${test_hosts[@]}"; do
        if ping -c 2 -W 5 "$host" &>/dev/null; then
            log_success "✅ $host 连接正常"
            connectivity_score=$((connectivity_score + 1))
        else
            log_warn "❌ $host 连接失败"
        fi
    done
    
    local success_rate=$((connectivity_score * 100 / total_tests))
    
    if [ $success_rate -ge 75 ]; then
        log_success "网络连接良好 ($success_rate%)"
        return 0
    elif [ $success_rate -ge 50 ]; then
        log_warn "网络连接一般 ($success_rate%)"
        return 1
    else
        log_error "网络连接较差 ($success_rate%)"
        return 2
    fi
}

test_dns_resolution() {
    log_info "测试DNS解析..."
    
    local test_domains=("google.com" "github.com" "docker.io")
    local dns_servers=("8.8.8.8" "1.1.1.1" "114.114.114.114")
    
    for domain in "${test_domains[@]}"; do
        local resolved=false
        
        for dns in "${dns_servers[@]}"; do
            if nslookup "$domain" "$dns" &>/dev/null; then
                log_success "✅ $domain 解析正常 (DNS: $dns)"
                resolved=true
                break
            fi
        done
        
        if [ "$resolved" = false ]; then
            log_warn "❌ $domain 解析失败"
        fi
    done
}

test_port_connectivity() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

test_http_response() {
    local url="$1"
    local expected_code="${2:-200}"
    local timeout="${3:-10}"
    
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$timeout" "$url" 2>/dev/null)
    
    if [ "$response_code" = "$expected_code" ]; then
        return 0
    else
        log_warn "HTTP响应异常: $url (期望: $expected_code, 实际: $response_code)"
        return 1
    fi
}

comprehensive_connectivity_test() {
    log_step "执行全面连接测试"
    
    local test_results=()
    
    if test_network_connectivity; then
        test_results+=("网络连接:✅")
    else
        test_results+=("网络连接:❌")
    fi
    
    test_dns_resolution
    test_results+=("DNS解析:✅")
    
    if netstat -tlnp | grep -q ":$APP_PORT "; then
        test_results+=("应用端口:✅")
        
        if test_http_response "http://127.0.0.1:$APP_PORT/health"; then
            test_results+=("应用HTTP:✅")
        else
            test_results+=("应用HTTP:❌")
        fi
    else
        test_results+=("应用端口:❌")
        test_results+=("应用HTTP:❌")
    fi
    
    if netstat -tlnp | grep -q ":80 "; then
        test_results+=("HTTP端口:✅")
        
        if test_http_response "http://127.0.0.1/health"; then
            test_results+=("代理HTTP:✅")
        else
            test_results+=("代理HTTP:❌")
        fi
    else
        test_results+=("HTTP端口:❌")
        test_results+=("代理HTTP:❌")
    fi
    
    if netstat -tlnp | grep -q ":443 "; then
        test_results+=("HTTPS端口:✅")
        
        if curl -f -k -s "https://127.0.0.1/health" >/dev/null; then
            test_results+=("代理HTTPS:✅")
        else
            test_results+=("代理HTTPS:❌")
        fi
    else
        test_results+=("HTTPS端口:⚠️")
        test_results+=("代理HTTPS:⚠️")
    fi
    
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "未知")
    if [ "$public_ip" != "未知" ]; then
        test_results+=("公网IP:✅($public_ip)")
        
        if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
            local resolved_ip=$(nslookup "$DOMAIN" 8.8.8.8 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")
            if [ "$resolved_ip" = "$public_ip" ]; then
                test_results+=("域名解析:✅")
            else
                test_results+=("域名解析:❌($resolved_ip)")
            fi
        fi
    else
        test_results+=("公网IP:❌")
    fi
    
    echo -e "\n${CYAN}=== 连接测试结果 ===${NC}"
    for result in "${test_results[@]}"; do
        echo -e "  $result"
    done
    
    log_success "连接测试完成"
}

diagnose_network_issues() {
    log_info "诊断网络问题..."
    
    echo -e "\n${CYAN}网络诊断报告：${NC}"
    
    echo -e "\n${YELLOW}网络接口状态：${NC}"
    ip addr show | grep -E "(inet|state)" | head -10
    
    echo -e "\n${YELLOW}默认路由：${NC}"
    ip route | grep default
    
    echo -e "\n${YELLOW}DNS配置：${NC}"
    cat /etc/resolv.conf | grep nameserver
    
    echo -e "\n${YELLOW}防火墙状态：${NC}"
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        firewall-cmd --list-all 2>/dev/null | head -10
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        ufw status 2>/dev/null
    fi
    
    echo -e "\n${YELLOW}端口监听状态：${NC}"
    netstat -tlnp | grep -E ":80|:443|:$APP_PORT"
    
    echo -e "\n${YELLOW}相关进程：${NC}"
    ps aux | grep -E "(notes-backend|nginx|docker)" | grep -v grep
}

fix_common_network_issues() {
    log_info "尝试修复常见网络问题..."
    
    if command -v systemctl &>/dev/null; then
        log_info "重启网络服务..."
        systemctl restart network 2>/dev/null || \
        systemctl restart networking 2>/dev/null || \
        systemctl restart NetworkManager 2>/dev/null || true
    fi
    
    if command -v systemd-resolve &>/dev/null; then
        log_info "刷新DNS缓存..."
        systemd-resolve --flush-caches 2>/dev/null || true
    fi
    
    if [ ! -f /etc/resolv.conf.backup ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true
    fi
    
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 114.114.114.114
nameserver 223.5.5.5
EOF
    
    log_info "DNS配置已更新"
    
    sleep 3
    if ping -c 2 8.8.8.8 &>/dev/null; then
        log_success "网络问题修复成功"
        return 0
    else
        log_warn "网络问题修复失败"
        return 1
    fi
}

generate_network_report() {
    local report_file="/tmp/notes-backend-network-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Notes Backend 网络状态报告"
        echo "生成时间: $(date)"
        echo "========================================"
        echo ""
        
        echo "网络接口信息:"
        ip addr show
        echo ""
        
        echo "路由表:"
        ip route
        echo ""
        
        echo "DNS配置:"
        cat /etc/resolv.conf
        echo ""
        
        echo "端口监听:"
        netstat -tlnp
        echo ""
        
        echo "防火墙状态:"
        if [ "$PACKAGE_MANAGER" = "yum" ]; then
            firewall-cmd --list-all 2>/dev/null || echo "firewalld未运行"
        elif [ "$PACKAGE_MANAGER" = "apt" ]; then
            ufw status 2>/dev/null || echo "ufw未启用"
        fi
        echo ""
        
        echo "连接测试:"
        comprehensive_connectivity_test
        
    } > "$report_file"
    
    log_info "网络报告已生成: $report_file"
    return 0
}


create_full_backup() {
    local backup_type="${1:-manual}"
    local backup_dir="/opt/notes-backend-backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="notes-backend-${backup_type}-${timestamp}"
    local backup_path="$backup_dir/$backup_name"
    
    log_info "创建完整系统备份: $backup_name"
    
    mkdir -p "$backup_path"
    
    backup_application_files "$backup_path"
    
    backup_configuration_files "$backup_path"
    
    backup_database "$backup_path"
    
    backup_system_services "$backup_path"
    
    create_backup_manifest "$backup_path"
    
    compress_backup "$backup_path"
    
    cleanup_old_backups "$backup_dir"
    
    log_success "完整备份创建完成: $backup_path.tar.gz"
    return 0
}

backup_application_files() {
    local backup_path="$1"
    local app_backup_dir="$backup_path/application"
    
    log_info "备份应用文件..."
    mkdir -p "$app_backup_dir"
    
    if [ -d "$PROJECT_DIR" ]; then
        cp -r "$PROJECT_DIR"/{notes-backend,go.mod,go.sum} "$app_backup_dir/" 2>/dev/null || true
        
        if [ -d "$PROJECT_DIR/cmd" ]; then
            cp -r "$PROJECT_DIR/cmd" "$app_backup_dir/" 2>/dev/null || true
        fi
        
        if [ -d "$PROJECT_DIR/internal" ]; then
            cp -r "$PROJECT_DIR/internal" "$app_backup_dir/" 2>/dev/null || true
        fi
        
        if [ -d "$PROJECT_DIR/scripts" ]; then
            cp -r "$PROJECT_DIR/scripts" "$app_backup_dir/" 2>/dev/null || true
        fi
        
        if [ -d "$PROJECT_DIR/uploads" ]; then
            local upload_size=$(du -sm "$PROJECT_DIR/uploads" 2>/dev/null | cut -f1 || echo "0")
            if [ "$upload_size" -lt 1000 ]; then  # 小于1GB
                cp -r "$PROJECT_DIR/uploads" "$app_backup_dir/" 2>/dev/null || true
                log_info "已备份上传文件 (${upload_size}MB)"
            else
                log_warn "上传文件过大，跳过备份 (${upload_size}MB)"
                echo "uploads_size=${upload_size}MB" > "$app_backup_dir/uploads_info.txt"
            fi
        fi
        
        log_success "应用文件备份完成"
    else
        log_warn "应用目录不存在，跳过应用文件备份"
    fi
}

backup_configuration_files() {
    local backup_path="$1"
    local config_backup_dir="$backup_path/configuration"
    
    log_info "备份配置文件..."
    mkdir -p "$config_backup_dir"
    
    if [ -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env" "$config_backup_dir/env.backup"
    fi
    
    if [ -d "$PROJECT_DIR/nginx" ]; then
        cp -r "$PROJECT_DIR/nginx" "$config_backup_dir/"
    fi
    
    if [ -f "$PROJECT_DIR/docker-compose.db.yml" ]; then
        cp "$PROJECT_DIR/docker-compose.db.yml" "$config_backup_dir/"
    fi
    
    mkdir -p "$config_backup_dir/system"
    
    if [ -f "/etc/docker/daemon.json" ]; then
        cp "/etc/docker/daemon.json" "$config_backup_dir/system/" 2>/dev/null || true
    fi
    
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        mkdir -p "$config_backup_dir/ssl"
        cp -r "/etc/letsencrypt/live/$DOMAIN" "$config_backup_dir/ssl/" 2>/dev/null || true
        cp -r "/etc/letsencrypt/renewal/$DOMAIN.conf" "$config_backup_dir/ssl/" 2>/dev/null || true
    fi
    
    log_success "配置文件备份完成"
}

backup_database() {
    local backup_path="$1"
    local db_backup_dir="$backup_path/database"
    
    log_info "备份数据库..."
    mkdir -p "$db_backup_dir"
    
    if [ -f "$PROJECT_DIR/.env" ]; then
        source "$PROJECT_DIR/.env"
    fi
    
    case "${DB_MODE:-local}" in
        "local")
            backup_local_database "$db_backup_dir"
            ;;
        "vercel")
            backup_vercel_database "$db_backup_dir"
            ;;
        "custom")
            backup_custom_database "$db_backup_dir"
            ;;
        *)
            log_warn "未知数据库类型，跳过数据库备份"
            ;;
    esac
}

backup_local_database() {
    local db_backup_dir="$1"
    
    if docker ps | grep -q "notes-postgres"; then
        log_info "备份本地PostgreSQL数据库..."
        
        local db_file="$db_backup_dir/postgres_backup_$(date +%Y%m%d_%H%M%S).sql"
        
        if docker exec notes-postgres pg_dump -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME" > "$db_file"; then
            log_success "本地数据库备份完成: $(basename $db_file)"
            
            gzip "$db_file"
            log_info "数据库备份已压缩"
        else
            log_error "本地数据库备份失败"
        fi
        
        echo "DB_TYPE=local" > "$db_backup_dir/db_config.txt"
        echo "DB_USER=$LOCAL_DB_USER" >> "$db_backup_dir/db_config.txt"
        echo "DB_NAME=$LOCAL_DB_NAME" >> "$db_backup_dir/db_config.txt"
    else
        log_warn "本地数据库容器未运行，跳过数据库备份"
    fi
}

backup_vercel_database() {
    local db_backup_dir="$1"
    
    if [ -n "$VERCEL_POSTGRES_URL" ] && command -v psql &>/dev/null; then
        log_info "备份Vercel数据库..."
        
        local db_file="$db_backup_dir/vercel_backup_$(date +%Y%m%d_%H%M%S).sql"
        
        if timeout 300 pg_dump "$VERCEL_POSTGRES_URL" > "$db_file"; then
            log_success "Vercel数据库备份完成: $(basename $db_file)"
            gzip "$db_file"
        else
            log_error "Vercel数据库备份失败"
        fi
        
        echo "DB_TYPE=vercel" > "$db_backup_dir/db_config.txt"
        echo "VERCEL_URL=${VERCEL_POSTGRES_URL:0:50}..." >> "$db_backup_dir/db_config.txt"
    else
        log_warn "Vercel数据库配置不完整，跳过数据库备份"
    fi
}

backup_custom_database() {
    local db_backup_dir="$1"
    
    if [ -n "$CUSTOM_DB_HOST" ] && command -v psql &>/dev/null; then
        log_info "备份自定义数据库..."
        
        local db_file="$db_backup_dir/custom_backup_$(date +%Y%m%d_%H%M%S).sql"
        local connection_string="postgresql://$CUSTOM_DB_USER:$CUSTOM_DB_PASSWORD@$CUSTOM_DB_HOST:$CUSTOM_DB_PORT/$CUSTOM_DB_NAME"
        
        if timeout 300 pg_dump "$connection_string" > "$db_file"; then
            log_success "自定义数据库备份完成: $(basename $db_file)"
            gzip "$db_file"
        else
            log_error "自定义数据库备份失败"
        fi
        
        echo "DB_TYPE=custom" > "$db_backup_dir/db_config.txt"
        echo "DB_HOST=$CUSTOM_DB_HOST" >> "$db_backup_dir/db_config.txt"
        echo "DB_NAME=$CUSTOM_DB_NAME" >> "$db_backup_dir/db_config.txt"
    else
        log_warn "自定义数据库配置不完整，跳过数据库备份"
    fi
}

backup_system_services() {
    local backup_path="$1"
    local service_backup_dir="$backup_path/services"
    
    log_info "备份系统服务配置..."
    mkdir -p "$service_backup_dir"
    
    local services=("notes-backend" "notes-nginx-http" "notes-nginx-https")
    
    for service in "${services[@]}"; do
        if [ -f "/etc/systemd/system/$service.service" ]; then
            cp "/etc/systemd/system/$service.service" "$service_backup_dir/"
        fi
    done
    
    crontab -l > "$service_backup_dir/crontab.backup" 2>/dev/null || true
    
    {
        echo "服务状态备份 - $(date)"
        echo "=========================="
        for service in "${services[@]}"; do
            echo "服务: $service"
            systemctl is-enabled "$service" 2>/dev/null || echo "未启用"
            systemctl is-active "$service" 2>/dev/null || echo "未运行"
            echo ""
        done
    } > "$service_backup_dir/service_status.txt"
    
    log_success "系统服务备份完成"
}

create_backup_manifest() {
    local backup_path="$1"
    local manifest_file="$backup_path/MANIFEST.txt"
    
    log_info "创建备份清单..."
    
    {
        echo "Notes Backend 备份清单"
        echo "备份时间: $(date)"
        echo "备份路径: $backup_path"
        echo "==============================="
        echo ""
        
        echo "系统信息:"
        echo "  操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "  内核版本: $(uname -r)"
        echo "  架构: $(uname -m)"
        echo ""
        
        echo "应用信息:"
        if [ -f "$PROJECT_DIR/go.mod" ]; then
            echo "  项目: $(head -1 $PROJECT_DIR/go.mod | awk '{print $2}')"
        fi
        if [ -f "$PROJECT_DIR/notes-backend" ]; then
            echo "  二进制文件: $(ls -lh $PROJECT_DIR/notes-backend | awk '{print $5}')"
        fi
        echo ""
        
        echo "服务状态:"
        systemctl is-active notes-backend 2>/dev/null && echo "  应用服务: 运行中" || echo "  应用服务: 已停止"
        if systemctl is-active notes-nginx-https 2>/dev/null; then
            echo "  代理服务: HTTPS模式"
        elif systemctl is-active notes-nginx-http 2>/dev/null; then
            echo "  代理服务: HTTP模式"
        else
            echo "  代理服务: 已停止"
        fi
        echo ""
        
        echo "备份内容:"
        find "$backup_path" -type f -exec ls -lh {} \; | awk '{print "  " $9 " (" $5 ")"}'
        echo ""
        
        echo "总大小: $(du -sh $backup_path | cut -f1)"
        
    } > "$manifest_file"
    
    log_success "备份清单创建完成"
}

compress_backup() {
    local backup_path="$1"
    local backup_dir=$(dirname "$backup_path")
    local backup_name=$(basename "$backup_path")
    
    log_info "压缩备份文件..."
    
    cd "$backup_dir"
    if tar -czf "${backup_name}.tar.gz" "$backup_name"; then
        log_success "备份压缩完成: ${backup_name}.tar.gz"
        
        rm -rf "$backup_name"
        
        local compressed_size=$(ls -lh "${backup_name}.tar.gz" | awk '{print $5}')
        log_info "压缩后大小: $compressed_size"
    else
        log_error "备份压缩失败"
        return 1
    fi
}

cleanup_old_backups() {
    local backup_dir="$1"
    local keep_days="${BACKUP_KEEP_DAYS:-30}"
    
    log_info "清理旧备份文件 (保留${keep_days}天)..."
    
    if [ -d "$backup_dir" ]; then
        find "$backup_dir" -name "notes-backend-*.tar.gz" -mtime +$keep_days -delete 2>/dev/null || true
        
        local remaining_backups=$(find "$backup_dir" -name "notes-backend-*.tar.gz" | wc -l)
        log_info "剩余备份文件: $remaining_backups 个"
        
        local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "未知")
        log_info "备份目录总大小: $total_size"
    fi
}

restore_from_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "从备份恢复系统: $(basename $backup_file)"
    
    echo -e "\n${YELLOW}⚠️ 警告：恢复操作将覆盖当前系统配置！${NC}"
    echo -e "${CYAN}是否继续恢复？ (y/N):${NC}"
    read -p "> " CONFIRM_RESTORE
    
    if [[ ! "$CONFIRM_RESTORE" =~ ^[Yy]$ ]]; then
        log_info "恢复操作已取消"
        return 0
    fi
    
    log_info "创建当前系统的紧急备份..."
    create_full_backup "emergency"
    
    stop_all_services
    
    local restore_dir="/tmp/notes-restore-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$restore_dir"
    
    if tar -xzf "$backup_file" -C "$restore_dir"; then
        log_success "备份文件解压完成"
    else
        log_error "备份文件解压失败"
        return 1
    fi
    
    local backup_content_dir=$(find "$restore_dir" -maxdepth 1 -type d -name "notes-backend-*" | head -1)
    
    if [ -z "$backup_content_dir" ]; then
        log_error "无法找到备份内容目录"
        return 1
    fi
    
    restore_application_files "$backup_content_dir"
    restore_configuration_files "$backup_content_dir"
    restore_database "$backup_content_dir"
    restore_system_services "$backup_content_dir"
    
    recompile_after_restore
    
    start_all_services
    
    if verify_restore_success; then
        log_success "系统恢复完成"
        
        rm -rf "$restore_dir"
        return 0
    else
        log_error "系统恢复验证失败"
        return 1
    fi
}

restore_application_files() {
    local backup_content_dir="$1"
    local app_backup_dir="$backup_content_dir/application"
    
    if [ -d "$app_backup_dir" ]; then
        log_info "恢复应用文件..."
        
        if [ -d "$PROJECT_DIR" ]; then
            mv "$PROJECT_DIR" "${PROJECT_DIR}.restore.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        
        mkdir -p "$PROJECT_DIR"
        
        cp -r "$app_backup_dir"/* "$PROJECT_DIR/"
        
        chmod +x "$PROJECT_DIR/notes-backend" 2>/dev/null || true
        chmod +x "$PROJECT_DIR/scripts"/*.sh 2>/dev/null || true
        
        log_success "应用文件恢复完成"
    else
        log_warn "备份中未找到应用文件"
    fi
}

restore_configuration_files() {
    local backup_content_dir="$1"
    local config_backup_dir="$backup_content_dir/configuration"
    
    if [ -d "$config_backup_dir" ]; then
        log_info "恢复配置文件..."
        
        if [ -f "$config_backup_dir/env.backup" ]; then
            cp "$config_backup_dir/env.backup" "$PROJECT_DIR/.env"
            chmod 600 "$PROJECT_DIR/.env"
        fi
        
        if [ -d "$config_backup_dir/nginx" ]; then
            cp -r "$config_backup_dir/nginx" "$PROJECT_DIR/"
        fi
        
        if [ -f "$config_backup_dir/docker-compose.db.yml" ]; then
            cp "$config_backup_dir/docker-compose.db.yml" "$PROJECT_DIR/"
        fi
        
        if [ -f "$config_backup_dir/system/daemon.json" ]; then
            cp "$config_backup_dir/system/daemon.json" "/etc/docker/" 2>/dev/null || true
        fi
        
        if [ -d "$config_backup_dir/ssl" ]; then
            cp -r "$config_backup_dir/ssl"/* "/etc/letsencrypt/live/" 2>/dev/null || true
        fi
        
        log_success "配置文件恢复完成"
    else
        log_warn "备份中未找到配置文件"
    fi
}

restore_database() {
    local backup_content_dir="$1"
    local db_backup_dir="$backup_content_dir/database"
    
    if [ -d "$db_backup_dir" ]; then
        log_info "恢复数据库..."
        
        local db_backup_file=$(find "$db_backup_dir" -name "*.sql.gz" -o -name "*.sql" | head -1)
        
        if [ -n "$db_backup_file" ]; then
            source "$db_backup_dir/db_config.txt" 2>/dev/null || true
            
            case "${DB_TYPE:-local}" in
                "local")
                    restore_local_database "$db_backup_file"
                    ;;
                "vercel"|"custom")
                    log_warn "外部数据库恢复需要手动操作"
                    log_info "数据库备份文件: $db_backup_file"
                    ;;
            esac
        else
            log_warn "未找到数据库备份文件"
        fi
    else
        log_warn "备份中未找到数据库"
    fi
}

restore_local_database() {
    local db_backup_file="$1"
    
    log_info "恢复本地数据库..."
    
    if [ -f "$PROJECT_DIR/docker-compose.db.yml" ]; then
        cd "$PROJECT_DIR"
        docker compose -f docker-compose.db.yml up -d
        
        sleep 15
        
        if [[ "$db_backup_file" == *.gz ]]; then
            zcat "$db_backup_file" | docker exec -i notes-postgres psql -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME"
        else
            cat "$db_backup_file" | docker exec -i notes-postgres psql -U "$LOCAL_DB_USER" "$LOCAL_DB_NAME"
        fi
        
        log_success "本地数据库恢复完成"
    else
        log_error "数据库配置文件不存在"
    fi
}

restore_system_services() {
    local backup_content_dir="$1"
    local service_backup_dir="$backup_content_dir/services"
    
    if [ -d "$service_backup_dir" ]; then
        log_info "恢复系统服务..."
        
        cp "$service_backup_dir"/*.service /etc/systemd/system/ 2>/dev/null || true
        
        systemctl daemon-reload
        
        if [ -f "$service_backup_dir/crontab.backup" ]; then
            crontab "$service_backup_dir/crontab.backup" 2>/dev/null || true
        fi
        
        log_success "系统服务恢复完成"
    else
        log_warn "备份中未找到系统服务"
    fi
}

recompile_after_restore() {
    if [ -f "$PROJECT_DIR/go.mod" ] && [ -f "$PROJECT_DIR/cmd/server/main.go" ]; then
        log_info "重新编译应用..."
        
        cd "$PROJECT_DIR"
        export PATH=$PATH:/usr/local/go/bin
        
        if go build -ldflags="-w -s" -o notes-backend cmd/server/main.go; then
            chmod +x notes-backend
            log_success "应用重新编译完成"
        else
            log_warn "应用重新编译失败"
        fi
    fi
}

stop_all_services() {
    log_info "停止所有服务..."
    
    systemctl stop notes-nginx-https 2>/dev/null || true
    systemctl stop notes-nginx-http 2>/dev/null || true
    systemctl stop notes-backend 2>/dev/null || true
    
    docker stop notes-nginx 2>/dev/null || true
    docker stop notes-postgres 2>/dev/null || true
}

start_all_services() {
    log_info "启动所有服务..."
    
    systemctl start notes-backend
    sleep 5
    
    if systemctl is-enabled notes-nginx-https 2>/dev/null; then
        systemctl start notes-nginx-https
    else
        systemctl start notes-nginx-http
    fi
}

verify_restore_success() {
    log_info "验证恢复结果..."
    
    if ! systemctl is-active --quiet notes-backend; then
        log_error "应用服务未启动"
        return 1
    fi
    
    sleep 10
    if ! curl -f -s "http://127.0.0.1:$APP_PORT/health" >/dev/null; then
        log_error "应用健康检查失败"
        return 1
    fi
    
    log_success "恢复验证通过"
    return 0
}

list_available_backups() {
    local backup_dir="/opt/notes-backend-backups"
    
    if [ ! -d "$backup_dir" ]; then
        log_warn "备份目录不存在"
        return 1
    fi
    
    echo -e "\n${CYAN}可用备份文件：${NC}"
    echo -e "${YELLOW}序号  文件名                           大小     时间${NC}"
    echo -e "----  --------------------------------  ------  ----------------"
    
    local count=1
    find "$backup_dir" -name "notes-backend-*.tar.gz" -type f | sort -r | while read backup_file; do
        local filename=$(basename "$backup_file")
        local filesize=$(ls -lh "$backup_file" | awk '{print $5}')
        local filetime=$(stat -c %y "$backup_file" | cut -d'.' -f1)
        
        printf "%-4d  %-32s  %-6s  %s\n" "$count" "$filename" "$filesize" "$filetime"
        count=$((count + 1))
    done
}

setup_automatic_backup() {
    log_info "设置自动备份..."
    
    cat > /usr/local/bin/notes-backend-backup.sh << 'EOF'
source /opt/notes-backend/paste-2.txt
create_full_backup "auto"
EOF
    
    chmod +x /usr/local/bin/notes-backend-backup.sh
    
    local backup_schedule="${BACKUP_SCHEDULE:-0 2 * * *}"
    
    (
        crontab -l 2>/dev/null | grep -v "notes-backend-backup"
        echo "$backup_schedule /usr/local/bin/notes-backend-backup.sh >> /var/log/notes-backup.log 2>&1"
    ) | crontab -
    
    log_success "自动备份已设置 (计划: $backup_schedule)"
}


monitor_system_performance() {
    local monitor_duration="${1:-60}"
    local report_file="/tmp/notes-backend-performance-$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "开始系统性能监控 (${monitor_duration}秒)..."
    
    {
        echo "Notes Backend 性能监控报告"
        echo "监控时间: $(date)"
        echo "监控时长: ${monitor_duration}秒"
        echo "========================================"
        echo ""
        
        echo "=== 系统信息 ==="
        echo "操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
        echo "内核版本: $(uname -r)"
        echo "架构: $(uname -m)"
        echo "运行时间: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
        echo ""
        
        echo "=== CPU信息 ==="
        echo "CPU型号: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
        echo "CPU核心数: $(nproc)"
        echo "CPU频率: $(grep 'cpu MHz' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs) MHz"
        echo ""
        
        echo "=== 内存信息 ==="
        free -h
        echo ""
        
        echo "=== 磁盘使用 ==="
        df -h | grep -E "(Filesystem|/dev/|tmpfs)" | head -10
        echo ""
        
        echo "=== 网络接口 ==="
        ip addr show | grep -E "(inet|state UP)" | head -10
        echo ""
        
    } > "$report_file"
    
    monitor_real_time_metrics "$report_file" "$monitor_duration"
    
    log_success "性能监控完成，报告保存至: $report_file"
    return 0
}

monitor_real_time_metrics() {
    local report_file="$1"
    local duration="$2"
    local interval=5
    local iterations=$((duration / interval))
    
    {
        echo "=== 实时性能数据 ==="
        echo "采样间隔: ${interval}秒"
        echo "时间                CPU%   内存%  磁盘%  负载    进程数  连接数"
        echo "------------------- -----  -----  -----  ------  ------  ------"
        
        for ((i=1; i<=iterations; i++)); do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            local cpu_usage=$(get_cpu_usage)
            local memory_usage=$(get_memory_usage)
            local disk_usage=$(get_disk_usage)
            local load_avg=$(get_load_average)
            local process_count=$(get_process_count)
            local connection_count=$(get_connection_count)
            
            printf "%-19s %5s  %5s  %5s  %6s  %6s  %6s\n" \
                "$timestamp" "$cpu_usage" "$memory_usage" "$disk_usage" \
                "$load_avg" "$process_count" "$connection_count"
            
            sleep "$interval"
        done
        
        echo ""
        
    } >> "$report_file"
    
    monitor_service_status "$report_file"
    
    monitor_network_stats "$report_file"
    
    monitor_process_analysis "$report_file"
}

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' | xargs
}

get_memory_usage() {
    free | awk 'NR==2{printf "%.1f", $3*100/($3+$4) }'
}

get_disk_usage() {
    df -h "$PROJECT_DIR" | awk 'NR==2{print $5}' | sed 's/%//'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'
}

get_process_count() {
    ps aux | wc -l
}

get_connection_count() {
    netstat -an | grep ESTABLISHED | wc -l
}

monitor_service_status() {
    local report_file="$1"
    
    {
        echo "=== 服务状态监控 ==="
        
        echo "Notes Backend 应用服务:"
        if systemctl is-active --quiet notes-backend; then
            echo "  状态: 运行中"
            echo "  PID: $(systemctl show notes-backend -p MainPID --value)"
            echo "  内存: $(systemctl show notes-backend -p MemoryCurrent --value | numfmt --to=iec)"
            echo "  启动时间: $(systemctl show notes-backend -p ActiveEnterTimestamp --value)"
        else
            echo "  状态: 未运行"
        fi
        echo ""
        
        echo "Nginx 代理服务:"
        if systemctl is-active --quiet notes-nginx-https; then
            echo "  模式: HTTPS"
            echo "  状态: 运行中"
        elif systemctl is-active --quiet notes-nginx-http; then
            echo "  模式: HTTP"
            echo "  状态: 运行中"
        else
            echo "  状态: 未运行"
        fi
        
        echo ""
        echo "Docker 容器:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(notes|postgres)" || echo "  无相关容器运行"
        echo ""
        
        echo "端口监听状态:"
        netstat -tlnp | grep -E ":80|:443|:$APP_PORT|:5432" | while read line; do
            echo "  $line"
        done
        echo ""
        
    } >> "$report_file"
}

monitor_network_stats() {
    local report_file="$1"
    
    {
        echo "=== 网络统计 ==="
        
        echo "网络接口流量:"
        cat /proc/net/dev | grep -E "(eth|ens|enp)" | head -5 | while read line; do
            local interface=$(echo "$line" | awk '{print $1}' | sed 's/://')
            local rx_bytes=$(echo "$line" | awk '{print $2}')
            local tx_bytes=$(echo "$line" | awk '{print $10}')
            
            printf "  %-10s RX: %10s bytes  TX: %10s bytes\n" \
                "$interface" "$(numfmt --to=iec $rx_bytes)" "$(numfmt --to=iec $tx_bytes)"
        done
        echo ""
        
        echo "连接状态统计:"
        netstat -an | awk '/^tcp/ {state[$6]++} END {for (i in state) print "  " i ": " state[i]}'
        echo ""
        
        echo "HTTP访问统计 (最近访问):"
        if [ -f "$PROJECT_DIR/logs/access.log" ]; then
            tail -100 "$PROJECT_DIR/logs/access.log" | awk '{print $9}' | sort | uniq -c | sort -nr | head -10 | while read count code; do
                echo "  状态码 $code: $count 次"
            done
        else
            echo "  无访问日志"
        fi
        echo ""
        
    } >> "$report_file"
}

monitor_process_analysis() {
    local report_file="$1"
    
    {
        echo "=== 进程分析 ==="
        
        echo "CPU占用最高的进程:"
        ps aux --sort=-%cpu | head -11 | tail -10 | awk '{printf "  %-20s %5s%% %8s %s\n", $11, $3, $4, $2}'
        echo ""
        
        echo "内存占用最高的进程:"
        ps aux --sort=-%mem | head -11 | tail -10 | awk '{printf "  %-20s %5s%% %8s %s\n", $11, $4, $3, $2}'
        echo ""
        
        echo "Notes Backend 相关进程:"
        ps aux | grep -E "(notes-backend|nginx|postgres)" | grep -v grep | while read line; do
            echo "  $line"
        done
        echo ""
        
        echo "系统资源使用概览:"
        echo "  平均负载: $(uptime | awk -F'load average:' '{print $2}')"
        echo "  总进程数: $(ps aux | wc -l)"
        echo "  运行进程: $(ps aux | awk '$8 ~ /R/' | wc -l)"
        echo "  休眠进程: $(ps aux | awk '$8 ~ /S/' | wc -l)"
        echo "  僵尸进程: $(ps aux | awk '$8 ~ /Z/' | wc -l)"
        echo ""
        
    } >> "$report_file"
}

monitor_application_performance() {
    local duration="${1:-300}"
    
    log_info "监控应用性能 (${duration}秒)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    
    local perf_report="/tmp/notes-app-performance-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Notes Backend 应用性能报告"
        echo "监控开始: $(date -d @$start_time)"
        echo "监控时长: ${duration}秒"
        echo "========================================"
        echo ""
        
    } > "$perf_report"
    
    monitor_response_times "$perf_report" "$end_time" &
    local response_pid=$!
    
    monitor_app_resources "$perf_report" "$end_time" &
    local resource_pid=$!
    
    monitor_database_performance "$perf_report" "$end_time" &
    local db_pid=$!
    
    wait $response_pid $resource_pid $db_pid
    
    generate_performance_summary "$perf_report"
    
    log_success "应用性能监控完成: $perf_report"
}

monitor_response_times() {
    local report_file="$1"
    local end_time="$2"
    
    {
        echo "=== 响应时间监控 ==="
        echo "时间                端点          响应时间(ms)  状态码"
        echo "------------------- ------------- ------------ -------"
        
        while [ $(date +%s) -lt $end_time ]; do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            local health_time=$(curl -w "%{time_total}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
            local health_code=$(curl -w "%{http_code}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
            local health_ms=$(echo "$health_time * 1000" | bc 2>/dev/null || echo "0")
            
            printf "%-19s %-13s %12.2f %7s\n" "$timestamp" "/health" "$health_ms" "$health_code"
            
            local api_time=$(curl -w "%{time_total}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/api/ping" 2>/dev/null)
            local api_code=$(curl -w "%{http_code}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/api/ping" 2>/dev/null)
            local api_ms=$(echo "$api_time * 1000" | bc 2>/dev/null || echo "0")
            
            if [ "$api_code" != "000" ]; then
                printf "%-19s %-13s %12.2f %7s\n" "$timestamp" "/api/ping" "$api_ms" "$api_code"
            fi
            
            sleep 10
        done
        echo ""
        
    } >> "$report_file"
}

monitor_app_resources() {
    local report_file="$1"
    local end_time="$2"
    
    {
        echo "=== 应用资源使用 ==="
        echo "时间                CPU%   内存MB  文件描述符  线程数"
        echo "------------------- -----  ------  ----------  ------"
        
        while [ $(date +%s) -lt $end_time ]; do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            local pid=$(pgrep notes-backend)
            
            if [ -n "$pid" ]; then
                local cpu_percent=$(ps -p "$pid" -o %cpu --no-headers | xargs)
                local memory_kb=$(ps -p "$pid" -o rss --no-headers | xargs)
                local memory_mb=$((memory_kb / 1024))
                local fd_count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
                local thread_count=$(ps -p "$pid" -o nlwp --no-headers | xargs)
                
                printf "%-19s %5s  %6d  %10d  %6s\n" \
                    "$timestamp" "$cpu_percent" "$memory_mb" "$fd_count" "$thread_count"
            else
                printf "%-19s %5s  %6s  %10s  %6s\n" \
                    "$timestamp" "N/A" "N/A" "N/A" "N/A"
            fi
            
            sleep 15
        done
        echo ""
        
    } >> "$report_file"
}

monitor_database_performance() {
    local report_file="$1"
    local end_time="$2"
    
    {
        echo "=== 数据库性能监控 ==="
        
        if docker ps | grep -q "notes-postgres"; then
            echo "时间                连接数  活跃查询  缓存命中率  数据库大小"
            echo "------------------- ------  --------  ----------  ----------"
            
            while [ $(date +%s) -lt $end_time ]; do
                local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                
                local connections=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
                local active_queries=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | xargs || echo "0")
                local cache_hit_ratio=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT round(sum(blks_hit)*100/sum(blks_hit+blks_read), 2) FROM pg_stat_database;" 2>/dev/null | xargs || echo "0")
                local db_size=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT pg_size_pretty(pg_database_size('$LOCAL_DB_NAME'));" 2>/dev/null | xargs || echo "N/A")
                
                printf "%-19s %6s  %8s  %10s%%  %10s\n" \
                    "$timestamp" "$connections" "$active_queries" "$cache_hit_ratio" "$db_size"
                
                sleep 20
            done
        else
            echo "本地数据库未运行，跳过数据库性能监控"
        fi
        echo ""
        
    } >> "$report_file"
}

generate_performance_summary() {
    local report_file="$1"
    
    {
        echo "=== 性能摘要 ==="
        
        echo "响应时间分析:"
        local avg_health_time=$(grep "/health" "$report_file" | awk '{sum+=$4; count++} END {if(count>0) print sum/count; else print 0}')
        local max_health_time=$(grep "/health" "$report_file" | awk '{if($4>max) max=$4} END {print max+0}')
        echo "  健康检查平均响应时间: $(printf "%.2f" $avg_health_time)ms"
        echo "  健康检查最大响应时间: $(printf "%.2f" $max_health_time)ms"
        
        echo ""
        echo "资源使用分析:"
        local avg_cpu=$(grep -E "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" "$report_file" | grep -v "N/A" | awk 'NF>=4 && $4~/^[0-9]/ {sum+=$4; count++} END {if(count>0) print sum/count; else print 0}')
        local avg_memory=$(grep -E "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" "$report_file" | grep -v "N/A" | awk 'NF>=5 && $5~/^[0-9]/ {sum+=$5; count++} END {if(count>0) print sum/count; else print 0}')
        echo "  平均CPU使用率: $(printf "%.2f" $avg_cpu)%"
        echo "  平均内存使用: $(printf "%.0f" $avg_memory)MB"
        
        echo ""
        echo "系统健康状况:"
        if systemctl is-active --quiet notes-backend; then
            echo "  应用服务: ✅ 正常运行"
        else
            echo "  应用服务: ❌ 未运行"
        fi
        
        if curl -f -s "http://127.0.0.1:$APP_PORT/health" >/dev/null; then
            echo "  健康检查: ✅ 通过"
        else
            echo "  健康检查: ❌ 失败"
        fi
        
        local current_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        echo "  系统负载: $current_load"
        
        echo ""
        echo "性能建议:"
        
        if (( $(echo "$avg_health_time > 1000" | bc -l) )); then
            echo "  ⚠️ 响应时间较慢，建议检查数据库性能和网络连接"
        fi
        
        if (( $(echo "$avg_cpu > 80" | bc -l) )); then
            echo "  ⚠️ CPU使用率较高，建议优化应用性能或增加服务器资源"
        fi
        
        if (( $(echo "$avg_memory > 1000" | bc -l) )); then
            echo "  ⚠️ 内存使用较高，建议检查内存泄漏或增加内存"
        fi
        
        if (( $(echo "$current_load > $(nproc)" | bc -l) )); then
            echo "  ⚠️ 系统负载较高，建议检查系统资源使用情况"
        fi
        
        echo "  ✅ 如无警告显示，系统性能良好"
        echo ""
        
    } >> "$report_file"
}

real_time_monitor() {
    log_info "启动实时性能监控 (按Ctrl+C退出)"
    
    trap 'echo -e "\n实时监控已停止"; exit 0' INT
    
    while true; do
        clear
        echo -e "${CYAN}Notes Backend 实时性能监控${NC}"
        echo -e "${YELLOW}时间: $(date)${NC}"
        echo -e "========================================"
        
        echo -e "\n${CYAN}系统概览:${NC}"
        echo -e "  负载: $(uptime | awk -F'load average:' '{print $2}')"
        echo -e "  CPU: $(get_cpu_usage)%"
        echo -e "  内存: $(get_memory_usage)%"
        echo -e "  磁盘: $(get_disk_usage)%"
        
        echo -e "\n${CYAN}服务状态:${NC}"
        if systemctl is-active --quiet notes-backend; then
            echo -e "  应用服务: ${GREEN}✅ 运行中${NC}"
            
            local app_pid=$(pgrep notes-backend)
            if [ -n "$app_pid" ]; then
                local app_cpu=$(ps -p "$app_pid" -o %cpu --no-headers | xargs)
                local app_mem=$(ps -p "$app_pid" -o rss --no-headers | xargs)
                local app_mem_mb=$((app_mem / 1024))
                echo -e "    CPU: ${app_cpu}%  内存: ${app_mem_mb}MB"
            fi
        else
            echo -e "  应用服务: ${RED}❌ 未运行${NC}"
        fi
        
        if systemctl is-active --quiet notes-nginx-https; then
            echo -e "  代理服务: ${GREEN}✅ HTTPS模式${NC}"
        elif systemctl is-active --quiet notes-nginx-http; then
            echo -e "  代理服务: ${GREEN}✅ HTTP模式${NC}"
        else
            echo -e "  代理服务: ${RED}❌ 未运行${NC}"
        fi
        
        echo -e "\n${CYAN}网络连接:${NC}"
        local connections=$(netstat -an | grep ESTABLISHED | wc -l)
        echo -e "  活跃连接: $connections"
        
        echo -e "  监听端口:"
        netstat -tlnp | grep -E ":80|:443|:$APP_PORT" | while read line; do
            local port=$(echo "$line" | awk '{print $4}' | cut -d':' -f2)
            echo -e "    $port ✅"
        done
        
        echo -e "\n${CYAN}响应时间:${NC}"
        local health_time=$(curl -w "%{time_total}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
        local health_ms=$(echo "$health_time * 1000" | bc 2>/dev/null || echo "0")
        local health_code=$(curl -w "%{http_code}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
        
        if [ "$health_code" = "200" ]; then
            echo -e "  健康检查: ${GREEN}✅ $(printf "%.2f" $health_ms)ms${NC}"
        else
            echo -e "  健康检查: ${RED}❌ 状态码:$health_code${NC}"
        fi
        
        echo -e "\n按 Ctrl+C 退出监控"
        sleep 3
    done
}

generate_performance_report() {
    local report_type="${1:-full}"
    local output_file="/tmp/notes-performance-report-$(date +%Y%m%d_%H%M%S).html"
    
    log_info "生成性能报告..."
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Notes Backend 性能报告</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 15px; border-radius: 5px; }
        .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background: #f9f9f9; border-radius: 3px; }
        .good { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Notes Backend 性能报告</h1>
        <p>生成时间: $(date)</p>
        <p>服务器: $(hostname)</p>
    </div>

    <div class="section">
        <h2>系统概览</h2>
        <div class="metric">
            <strong>CPU使用率:</strong> <span class="$([ $(echo "$(get_cpu_usage) > 80" | bc) -eq 1 ] && echo "error" || echo "good")">$(get_cpu_usage)%</span>
        </div>
        <div class="metric">
            <strong>内存使用率:</strong> <span class="$([ $(echo "$(get_memory_usage) > 80" | bc) -eq 1 ] && echo "error" || echo "good")">$(get_memory_usage)%</span>
        </div>
        <div class="metric">
            <strong>磁盘使用率:</strong> <span class="$([ $(get_disk_usage) -gt 80 ] && echo "error" || echo "good")">$(get_disk_usage)%</span>
        </div>
        <div class="metric">
            <strong>系统负载:</strong> $(get_load_average)
        </div>
    </div>

    <div class="section">
        <h2>服务状态</h2>
        <table>
            <tr><th>服务</th><th>状态</th><th>备注</th></tr>
EOF

    if systemctl is-active --quiet notes-backend; then
        echo "            <tr><td>Notes Backend</td><td class=\"good\">✅ 运行中</td><td>$(systemctl show notes-backend -p ActiveEnterTimestamp --value)</td></tr>" >> "$output_file"
    else
        echo "            <tr><td>Notes Backend</td><td class=\"error\">❌ 未运行</td><td>服务已停止</td></tr>" >> "$output_file"
    fi
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo "            <tr><td>Nginx代理</td><td class=\"good\">✅ HTTPS模式</td><td>SSL证书已配置</td></tr>" >> "$output_file"
    elif systemctl is-active --quiet notes-nginx-http; then
        echo "            <tr><td>Nginx代理</td><td class=\"warning\">⚠️ HTTP模式</td><td>建议配置HTTPS</td></tr>" >> "$output_file"
    else
        echo "            <tr><td>Nginx代理</td><td class=\"error\">❌ 未运行</td><td>代理服务已停止</td></tr>" >> "$output_file"
    fi

    cat >> "$output_file" << EOF
        </table>
    </div>

    <div class="section">
        <h2>性能测试</h2>
EOF

    local health_time=$(curl -w "%{time_total}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
    local health_code=$(curl -w "%{http_code}" -s -o /dev/null "http://127.0.0.1:$APP_PORT/health" 2>/dev/null)
    local health_ms=$(echo "$health_time * 1000" | bc 2>/dev/null || echo "0")

    cat >> "$output_file" << EOF
        <table>
            <tr><th>测试项目</th><th>结果</th><th>响应时间</th><th>状态</th></tr>
            <tr>
                <td>健康检查</td>
                <td>/health</td>
                <td>$(printf "%.2f" $health_ms)ms</td>
                <td class="$([ "$health_code" = "200" ] && echo "good" || echo "error")">$health_code</td>
            </tr>
        </table>
    </div>

    <div class="section">
        <h2>资源使用详情</h2>
        <h3>进程信息</h3>
        <table>
            <tr><th>进程</th><th>PID</th><th>CPU%</th><th>内存</th><th>状态</th></tr>
EOF

    ps aux | grep -E "(notes-backend|nginx|postgres)" | grep -v grep | while read line; do
        local user=$(echo "$line" | awk '{print $1}')
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}' | cut -c1-50)
        
        echo "            <tr><td>$cmd</td><td>$pid</td><td>$cpu%</td><td>$mem%</td><td class=\"good\">运行中</td></tr>" >> "$output_file"
    done

    cat >> "$output_file" << EOF
        </table>
        
        <h3>网络连接</h3>
        <table>
            <tr><th>协议</th><th>本地地址</th><th>状态</th><th>进程</th></tr>
EOF

    netstat -tlnp | grep -E ":80|:443|:$APP_PORT|:5432" | while read line; do
        local proto=$(echo "$line" | awk '{print $1}')
        local local_addr=$(echo "$line" | awk '{print $4}')
        local state=$(echo "$line" | awk '{print $6}')
        local process=$(echo "$line" | awk '{print $7}' | cut -d'/' -f2)
        
        echo "            <tr><td>$proto</td><td>$local_addr</td><td>$state</td><td>$process</td></tr>" >> "$output_file"
    done

    cat >> "$output_file" << EOF
        </table>
    </div>

    <div class="section">
        <h2>建议和优化</h2>
        <ul>
EOF

    local cpu_usage=$(get_cpu_usage)
    local memory_usage=$(get_memory_usage)
    local disk_usage=$(get_disk_usage)
    
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo "            <li class=\"warning\">CPU使用率较高($cpu_usage%)，建议优化应用性能或升级服务器</li>" >> "$output_file"
    fi
    
    if (( $(echo "$memory_usage > 80" | bc -l) )); then
        echo "            <li class=\"warning\">内存使用率较高($memory_usage%)，建议检查内存泄漏或增加内存</li>" >> "$output_file"
    fi
    
    if [ "$disk_usage" -gt 80 ]; then
        echo "            <li class=\"warning\">磁盘使用率较高($disk_usage%)，建议清理日志文件或扩容磁盘</li>" >> "$output_file"
    fi
    
    if [ "$health_code" != "200" ]; then
        echo "            <li class=\"error\">健康检查失败，请检查应用状态和配置</li>" >> "$output_file"
    fi
    
    if ! systemctl is-active --quiet notes-nginx-https; then
        echo "            <li class=\"warning\">建议配置HTTPS以提高安全性</li>" >> "$output_file"
    fi

    cat >> "$output_file" << EOF
            <li class=\"good\">定期备份数据库和配置文件</li>
            <li class=\"good\">监控系统日志以及早发现问题</li>
            <li class=\"good\">保持系统和应用程序更新</li>
        </ul>
    </div>

    <div class="section">
        <h2>系统信息</h2>
        <table>
            <tr><th>项目</th><th>值</th></tr>
            <tr><td>操作系统</td><td>$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)</td></tr>
            <tr><td>内核版本</td><td>$(uname -r)</td></tr>
            <tr><td>架构</td><td>$(uname -m)</td></tr>
            <tr><td>运行时间</td><td>$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')</td></tr>
            <tr><td>CPU核心数</td><td>$(nproc)</td></tr>
            <tr><td>总内存</td><td>$(free -h | awk 'NR==2{print $2}')</td></tr>
            <tr><td>磁盘总容量</td><td>$(df -h $PROJECT_DIR | awk 'NR==2{print $2}')</td></tr>
        </table>
    </div>

    <footer style="margin-top: 40px; padding: 20px; background: #f0f0f0; text-align: center;">
        <p>报告生成时间: $(date)</p>
        <p>Notes Backend Performance Monitor v1.0</p>
    </footer>

</body>
</html>
EOF

    log_success "性能报告已生成: $output_file"
    echo -e "${CYAN}使用浏览器打开查看: file://$output_file${NC}"
}

performance_optimization_suggestions() {
    log_info "分析系统性能并生成优化建议..."
    
    echo -e "\n${CYAN}=== 性能优化建议 ===${NC}"
    
    local cpu_usage=$(get_cpu_usage)
    echo -e "\n${YELLOW}CPU优化:${NC}"
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo -e "  ${RED}⚠️ CPU使用率高($cpu_usage%)${NC}"
        echo -e "    - 检查应用程序是否有死循环或计算密集任务"
        echo -e "    - 考虑使用缓存减少重复计算"
        echo -e "    - 优化数据库查询"
        echo -e "    - 考虑升级到更高配置的服务器"
    else
        echo -e "  ${GREEN}✅ CPU使用率正常($cpu_usage%)${NC}"
    fi
    
    local memory_usage=$(get_memory_usage)
    echo -e "\n${YELLOW}内存优化:${NC}"
    if (( $(echo "$memory_usage > 80" | bc -l) )); then
        echo -e "  ${RED}⚠️ 内存使用率高($memory_usage%)${NC}"
        echo -e "    - 检查是否有内存泄漏"
        echo -e "    - 优化应用程序的内存使用"
        echo -e "    - 考虑增加服务器内存"
        echo -e "    - 配置swap文件作为临时缓解"
    else
        echo -e "  ${GREEN}✅ 内存使用率正常($memory_usage%)${NC}"
    fi
    
    local disk_usage=$(get_disk_usage)
    echo -e "\n${YELLOW}磁盘优化:${NC}"
    if [ "$disk_usage" -gt 80 ]; then
        echo -e "  ${RED}⚠️ 磁盘使用率高($disk_usage%)${NC}"
        echo -e "    - 清理旧的日志文件和备份文件"
        echo -e "    - 压缩或删除不需要的上传文件"
        echo -e "    - 配置日志轮转"
        echo -e "    - 考虑增加磁盘容量"
        
        echo -e "    - 大文件目录分析:"
        du -sh "$PROJECT_DIR"/* 2>/dev/null | sort -hr | head -5 | while read size dir; do
            echo -e "      $size $dir"
        done
    else
        echo -e "  ${GREEN}✅ 磁盘使用率正常($disk_usage%)${NC}"
    fi
    
    echo -e "\n${YELLOW}网络优化:${NC}"
    local connection_count=$(get_connection_count)
    if [ "$connection_count" -gt 100 ]; then
        echo -e "  ${YELLOW}⚠️ 网络连接数较多($connection_count)${NC}"
        echo -e "    - 检查是否有异常连接"
        echo -e "    - 优化连接池配置"
        echo -e "    - 考虑使用CDN分发静态资源"
    else
        echo -e "  ${GREEN}✅ 网络连接正常($connection_count)${NC}"
    fi
    
    echo -e "\n${YELLOW}应用优化:${NC}"
    local app_pid=$(pgrep notes-backend)
    if [ -n "$app_pid" ]; then
        local app_memory=$(ps -p "$app_pid" -o rss --no-headers | xargs)
        local app_memory_mb=$((app_memory / 1024))
        
        if [ "$app_memory_mb" -gt 500 ]; then
            echo -e "  ${YELLOW}⚠️ 应用内存使用较高(${app_memory_mb}MB)${NC}"
            echo -e "    - 检查是否有内存泄漏"
            echo -e "    - 优化数据结构和算法"
            echo -e "    - 定期重启应用程序"
        else
            echo -e "  ${GREEN}✅ 应用内存使用正常(${app_memory_mb}MB)${NC}"
        fi
        
        local fd_count=$(ls /proc/$app_pid/fd 2>/dev/null | wc -l)
        if [ "$fd_count" -gt 1000 ]; then
            echo -e "  ${YELLOW}⚠️ 文件描述符使用较多($fd_count)${NC}"
            echo -e "    - 检查是否正确关闭文件和网络连接"
            echo -e "    - 增加系统文件描述符限制"
        fi
    else
        echo -e "  ${RED}❌ 应用程序未运行${NC}"
    fi
    
    echo -e "\n${YELLOW}数据库优化:${NC}"
    if docker ps | grep -q "notes-postgres"; then
        local db_connections=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
        
        if [ "$db_connections" -gt 50 ]; then
            echo -e "  ${YELLOW}⚠️ 数据库连接数较多($db_connections)${NC}"
            echo -e "    - 优化应用程序的数据库连接管理"
            echo -e "    - 配置连接池"
            echo -e "    - 检查是否有长时间运行的查询"
        else
            echo -e "  ${GREEN}✅ 数据库连接正常($db_connections)${NC}"
        fi
        
        local cache_hit=$(docker exec notes-postgres psql -U "$LOCAL_DB_USER" -d "$LOCAL_DB_NAME" -t -c "SELECT round(sum(blks_hit)*100/sum(blks_hit+blks_read), 2) FROM pg_stat_database;" 2>/dev/null | xargs || echo "0")
        
        if (( $(echo "$cache_hit < 95" | bc -l) )); then
            echo -e "  ${YELLOW}⚠️ 数据库缓存命中率较低($cache_hit%)${NC}"
            echo -e "    - 增加shared_buffers配置"
            echo -e "    - 优化查询语句"
            echo -e "    - 增加服务器内存"
        else
            echo -e "  ${GREEN}✅ 数据库缓存命中率良好($cache_hit%)${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️ 使用外部数据库${NC}"
        echo -e "    - 确保数据库服务器性能良好"
        echo -e "    - 优化网络延迟"
    fi
    
    echo -e "\n${YELLOW}安全优化:${NC}"
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "  ${GREEN}✅ HTTPS已启用${NC}"
    else
        echo -e "  ${RED}⚠️ 建议启用HTTPS${NC}"
        echo -e "    - 运行 ./enable-https.sh 配置SSL证书"
        echo -e "    - 强制HTTP重定向到HTTPS"
    fi
    
    echo -e "\n${YELLOW}监控建议:${NC}"
    echo -e "  ${CYAN}建议配置以下监控:${NC}"
    echo -e "    - 设置性能监控告警"
    echo -e "    - 定期备份数据库"
    echo -e "    - 监控日志文件大小"
    echo -e "    - 设置健康检查告警"
    
    echo -e "\n${YELLOW}维护建议:${NC}"
    echo -e "  ${CYAN}定期维护任务:${NC}"
    echo -e "    - 每周重启应用程序"
    echo -e "    - 每月清理日志文件"
    echo -e "    - 定期更新系统和应用"
    echo -e "    - 测试备份恢复流程"
}

auto_performance_tuning() {
    log_info "执行自动性能调优..."
    
    optimize_system_parameters
    
    optimize_application_config
    
    optimize_database_config
    
    optimize_nginx_config
    
    log_success "自动性能调优完成"
}

optimize_system_parameters() {
    log_info "优化系统参数..."
    
    if ! grep -q "notes-backend" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'

* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
        log_info "已优化文件描述符限制"
    fi
    
    if [ ! -f /etc/sysctl.d/99-notes-backend.conf ]; then
        cat > /etc/sysctl.d/99-notes-backend.conf << 'EOF'
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
vm.swappiness = 10
EOF
        sysctl -p /etc/sysctl.d/99-notes-backend.conf
        log_info "已优化内核参数"
    fi
}

optimize_application_config() {
    log_info "优化应用配置..."
    
    if [ -f "$PROJECT_DIR/.env" ]; then
        if ! grep -q "GOMAXPROCS" "$PROJECT_DIR/.env"; then
            echo "" >> "$PROJECT_DIR/.env"
            echo "# 性能优化配置" >> "$PROJECT_DIR/.env"
            echo "GOMAXPROCS=$(nproc)" >> "$PROJECT_DIR/.env"
            echo "GOGC=100" >> "$PROJECT_DIR/.env"
            log_info "已添加Go运行时优化配置"
        fi
    fi
}

optimize_database_config() {
    log_info "优化数据库配置..."
    
    if [ -f "$PROJECT_DIR/docker-compose.db.yml" ]; then
        local total_memory_mb=$(free -m | awk 'NR==2{print $2}')
        local shared_buffers=$((total_memory_mb / 4))
        local effective_cache_size=$((total_memory_mb * 3 / 4))
        
        log_info "根据系统内存(${total_memory_mb}MB)优化数据库配置"
        log_info "shared_buffers: ${shared_buffers}MB"
        log_info "effective_cache_size: ${effective_cache_size}MB"
    fi
}

optimize_nginx_config() {
    log_info "优化Nginx配置..."
    
    local worker_processes=$(nproc)
    local worker_connections=1024
    
    log_info "worker_processes: $worker_processes"
    log_info "worker_connections: $worker_connections"
}

performance_benchmark() {
    local duration="${1:-60}"
    local concurrent="${2:-10}"
    
    log_info "执行性能基准测试 (${duration}秒, ${concurrent}并发)"
    
    if ! command -v ab &>/dev/null; then
        log_info "安装Apache Bench工具..."
        if [ "$PACKAGE_MANAGER" = "apt" ]; then
            apt install -y apache2-utils
        elif [ "$PACKAGE_MANAGER" = "yum" ]; then
            $PACKAGE_MANAGER install -y httpd-tools
        fi
    fi
    
    local benchmark_file="/tmp/notes-benchmark-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Notes Backend 性能基准测试"
        echo "测试时间: $(date)"
        echo "测试时长: ${duration}秒"
        echo "并发数: $concurrent"
        echo "========================================"
        echo ""
        
    } > "$benchmark_file"
    
    log_info "测试健康检查端点..."
    {
        echo "=== 健康检查端点测试 ==="
        ab -t "$duration" -c "$concurrent" "http://127.0.0.1:$APP_PORT/health"
        echo ""
        
    } >> "$benchmark_file"
    
    if curl -f -s "http://127.0.0.1:$APP_PORT/api/ping" >/dev/null 2>&1; then
        log_info "测试API端点..."
        {
            echo "=== API端点测试 ==="
            ab -t "$duration" -c "$concurrent" "http://127.0.0.1:$APP_PORT/api/ping"
            echo ""
            
        } >> "$benchmark_file"
    fi
    
    log_success "性能基准测试完成: $benchmark_file"
}


setup_log_rotation() {
    log_info "配置日志轮转..."
    
    cat > /etc/logrotate.d/notes-backend << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 root root
    postrotate
        systemctl reload notes-backend 2>/dev/null || true
    endscript
}

/var/log/notes-*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 root root
}
EOF

    cat > /etc/logrotate.d/notes-nginx << EOF
$PROJECT_DIR/logs/nginx/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    create 644 root root
    postrotate
        docker exec notes-nginx nginx -s reload 2>/dev/null || true
    endscript
}
EOF

    if logrotate -d /etc/logrotate.d/notes-backend &>/dev/null; then
        log_success "日志轮转配置完成"
    else
        log_warn "日志轮转配置可能有问题"
    fi
}

monitor_logs_realtime() {
    local log_type="${1:-all}"
    
    log_info "启动实时日志监控 (类型: $log_type, 按Ctrl+C退出)"
    
    case "$log_type" in
        "app"|"application")
            monitor_application_logs
            ;;
        "nginx"|"proxy")
            monitor_nginx_logs
            ;;
        "system")
            monitor_system_logs
            ;;
        "database"|"db")
            monitor_database_logs
            ;;
        "error")
            monitor_error_logs
            ;;
        "all"|*)
            monitor_all_logs
            ;;
    esac
}

monitor_application_logs() {
    echo -e "${CYAN}=== Notes Backend 应用日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    if systemctl is-active --quiet notes-backend; then
        journalctl -u notes-backend -f --no-pager
    else
        echo -e "${RED}应用服务未运行${NC}"
        
        if [ -f "$PROJECT_DIR/logs/app.log" ]; then
            echo -e "${CYAN}监控应用日志文件...${NC}"
            tail -f "$PROJECT_DIR/logs/app.log"
        fi
    fi
}

monitor_nginx_logs() {
    echo -e "${CYAN}=== Nginx 代理日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    if docker ps | grep -q "notes-nginx"; then
        echo -e "${GREEN}监控Nginx容器日志...${NC}"
        docker logs -f notes-nginx
    else
        echo -e "${RED}Nginx容器未运行${NC}"
        
        if [ -f "$PROJECT_DIR/logs/access.log" ]; then
            echo -e "${CYAN}监控访问日志文件...${NC}"
            tail -f "$PROJECT_DIR/logs/access.log"
        fi
    fi
}

monitor_system_logs() {
    echo -e "${CYAN}=== 系统日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    journalctl -f --no-pager | grep -E "(notes|error|warn|fail)"
}

monitor_database_logs() {
    echo -e "${CYAN}=== 数据库日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    if docker ps | grep -q "notes-postgres"; then
        echo -e "${GREEN}监控PostgreSQL容器日志...${NC}"
        docker logs -f notes-postgres
    else
        echo -e "${RED}数据库容器未运行${NC}"
    fi
}

monitor_error_logs() {
    echo -e "${CYAN}=== 错误日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    if command -v multitail &>/dev/null; then
        multitail \
            -l "journalctl -u notes-backend -f --no-pager | grep -i error" \
            -l "docker logs -f notes-nginx 2>&1 | grep -i error" \
            -l "docker logs -f notes-postgres 2>&1 | grep -i error"
    else
        {
            journalctl -u notes-backend -f --no-pager | grep -i error &
            docker logs -f notes-nginx 2>&1 | grep -i error &
            docker logs -f notes-postgres 2>&1 | grep -i error &
            wait
        }
    fi
}

monitor_all_logs() {
    echo -e "${CYAN}=== 综合日志监控 ===${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    echo -e "========================================"
    
    cat > /tmp/notes_log_monitor.sh << 'EOF'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

{
    journalctl -u notes-backend -f --no-pager | sed "s/^/[APP] /" &
    docker logs -f notes-nginx 2>&1 | sed "s/^/[NGINX] /" &
    docker logs -f notes-postgres 2>&1 | sed "s/^/[DB] /" &
    wait
} | while read line; do
    timestamp=$(date '+%H:%M:%S')
    if [[ "$line" == *"[APP]"* ]]; then
        echo -e "${GREEN}[$timestamp]${NC} $line"
    elif [[ "$line" == *"[NGINX]"* ]]; then
        echo -e "${BLUE}[$timestamp]${NC} $line"
    elif [[ "$line" == *"[DB]"* ]]; then
        echo -e "${PURPLE}[$timestamp]${NC} $line"
    else
        echo -e "${YELLOW}[$timestamp]${NC} $line"
    fi
done
EOF
    
    chmod +x /tmp/notes_log_monitor.sh
    bash /tmp/notes_log_monitor.sh
    rm -f /tmp/notes_log_monitor.sh
}

analyze_logs() {
    local analysis_period="${1:-1}"  # 默认分析最近1天
    local report_file="/tmp/notes-log-analysis-$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "分析最近 ${analysis_period} 天的日志..."
    
    {
        echo "Notes Backend 日志分析报告"
        echo "分析时间: $(date)"
        echo "分析周期: 最近 ${analysis_period} 天"
        echo "========================================"
        echo ""
        
    } > "$report_file"
    
    analyze_application_logs "$report_file" "$analysis_period"
    
    analyze_nginx_access_logs "$report_file" "$analysis_period"
    
    analyze_error_logs "$report_file" "$analysis_period"
    
    analyze_system_logs "$report_file" "$analysis_period"
    
    generate_log_summary "$report_file"
    
    log_success "日志分析完成: $report_file"
}

analyze_application_logs() {
    local report_file="$1"
    local period="$2"
    
    {
        echo "=== 应用日志分析 ==="
        
        local app_starts=$(journalctl -u notes-backend --since "${period} days ago" | grep -c "Started\|启动" || echo "0")
        local app_stops=$(journalctl -u notes-backend --since "${period} days ago" | grep -c "Stopped\|停止" || echo "0")
        
        echo "应用启动次数: $app_starts"
        echo "应用停止次数: $app_stops"
        
        local app_errors=$(journalctl -u notes-backend --since "${period} days ago" | grep -ci "error\|错误" || echo "0")
        local app_warnings=$(journalctl -u notes-backend --since "${period} days ago" | grep -ci "warn\|警告" || echo "0")
        
        echo "错误消息数量: $app_errors"
        echo "警告消息数量: $app_warnings"
        
        echo ""
        echo "最近的错误消息:"
        journalctl -u notes-backend --since "${period} days ago" | grep -i "error\|错误" | tail -5 | while read line; do
            echo "  $line"
        done
        
        echo ""
        
    } >> "$report_file"
}

analyze_nginx_access_logs() {
    local report_file="$1"
    local period="$2"
    
    {
        echo "=== Nginx 访问日志分析 ==="
        
        local access_log="$PROJECT_DIR/logs/access.log"
        
        if [ -f "$access_log" ]; then
            local total_requests=$(wc -l < "$access_log")
            echo "总请求数: $total_requests"
            
            echo ""
            echo "HTTP状态码统计:"
            awk '{print $9}' "$access_log" | sort | uniq -c | sort -nr | head -10 | while read count code; do
                echo "  $code: $count 次"
            done
            
            echo ""
            echo "访问最多的IP地址:"
            awk '{print $1}' "$access_log" | sort | uniq -c | sort -nr | head -10 | while read count ip; do
                echo "  $ip: $count 次"
            done
            
            echo ""
            echo "访问最多的URL:"
            awk '{print $7}' "$access_log" | sort | uniq -c | sort -nr | head -10 | while read count url; do
                echo "  $url: $count 次"
            done
            
            echo ""
            echo "错误请求 (4xx, 5xx):"
            awk '$9 >= 400 {print $9}' "$access_log" | sort | uniq -c | sort -nr | while read count code; do
                echo "  $code: $count 次"
            done
            
        else
            echo "访问日志文件不存在: $access_log"
        fi
        
        echo ""
        
    } >> "$report_file"
}

analyze_error_logs() {
    local report_file="$1"
    local period="$2"
    
    {
        echo "=== 错误日志分析 ==="
        
        local system_errors=$(journalctl --since "${period} days ago" | grep -ci "error\|failed\|fault" || echo "0")
        echo "系统错误数量: $system_errors"
        
        local docker_errors=$(journalctl --since "${period} days ago" | grep -ci "docker.*error" || echo "0")
        echo "Docker错误数量: $docker_errors"
        
        local network_errors=$(journalctl --since "${period} days ago" | grep -ci "network.*error\|connection.*failed" || echo "0")
        echo "网络错误数量: $network_errors"
        
        echo ""
        echo "最近的严重错误:"
        journalctl --since "${period} days ago" | grep -i "critical\|fatal\|panic" | tail -5 | while read line; do
            echo "  $line"
        done
        
        echo ""
        
    } >> "$report_file"
}

analyze_system_logs() {
    local report_file="$1"
    local period="$2"
    
    {
        echo "=== 系统日志分析 ==="
        
        local reboots=$(journalctl --since "${period} days ago" | grep -c "System reboot\|Startup finished" || echo "0")
        echo "系统重启次数: $reboots"
        
        echo ""
        echo "服务重启统计:"
        for service in notes-backend notes-nginx-http notes-nginx-https docker; do
            local restarts=$(journalctl -u "$service" --since "${period} days ago" | grep -c "Started\|Stopped" || echo "0")
            echo "  $service: $restarts 次"
        done
        
        echo ""
        echo "资源使用警告:"
        local memory_warnings=$(journalctl --since "${period} days ago" | grep -ci "out of memory\|oom" || echo "0")
        local disk_warnings=$(journalctl --since "${period} days ago" | grep -ci "no space\|disk full" || echo "0")
        echo "  内存不足警告: $memory_warnings"
        echo "  磁盘空间警告: $disk_warnings"
        
        echo ""
        
    } >> "$report_file"
}

generate_log_summary() {
    local report_file="$1"
    
    {
        echo "=== 日志统计摘要 ==="
        
        echo "日志文件大小统计:"
        
        if [ -d "$PROJECT_DIR/logs" ]; then
            local total_log_size=$(du -sh "$PROJECT_DIR/logs" 2>/dev/null | cut -f1 || echo "0")
            echo "  应用日志总大小: $total_log_size"
            
            find "$PROJECT_DIR/logs" -name "*.log" -type f | while read logfile; do
                local filesize=$(du -sh "$logfile" | cut -f1)
                local filename=$(basename "$logfile")
                echo "    $filename: $filesize"
            done
        fi
        
        local journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $7}' || echo "未知")
        echo "  系统日志大小: $journal_size"
        
        echo ""
        
        echo "日志增长趋势:"
        if [ -f "$PROJECT_DIR/logs/access.log" ]; then
            local today_logs=$(grep "$(date '+%d/%b/%Y')" "$PROJECT_DIR/logs/access.log" | wc -l)
            local yesterday_logs=$(grep "$(date -d yesterday '+%d/%b/%Y')" "$PROJECT_DIR/logs/access.log" | wc -l)
            echo "  今日访问日志: $today_logs 条"
            echo "  昨日访问日志: $yesterday_logs 条"
            
            if [ "$yesterday_logs" -gt 0 ]; then
                local growth_rate=$(( (today_logs - yesterday_logs) * 100 / yesterday_logs ))
                echo "  日增长率: $growth_rate%"
            fi
        fi
        
        echo ""
        
        echo "=== 维护建议 ==="
        
        if [ -d "$PROJECT_DIR/logs" ]; then
            find "$PROJECT_DIR/logs" -name "*.log" -size +100M | while read largefile; do
                echo "⚠️ 大型日志文件: $(basename "$largefile") (建议清理或轮转)"
            done
        fi
        
        local total_requests=$([ -f "$PROJECT_DIR/logs/access.log" ] && wc -l < "$PROJECT_DIR/logs/access.log" || echo "0")
        local error_requests=$([ -f "$PROJECT_DIR/logs/access.log" ] && awk '$9 >= 400' "$PROJECT_DIR/logs/access.log" | wc -l || echo "0")
        
        if [ "$total_requests" -gt 0 ]; then
            local error_rate=$(( error_requests * 100 / total_requests ))
            if [ "$error_rate" -gt 5 ]; then
                echo "⚠️ 错误请求率较高: $error_rate% (建议检查应用程序)"
            fi
        fi
        
        echo "✅ 建议定期运行日志清理和分析"
        echo "✅ 建议监控日志文件大小增长"
        echo "✅ 建议设置日志告警规则"
        
    } >> "$report_file"
}

cleanup_logs() {
    local keep_days="${1:-30}"
    local cleanup_report="/tmp/notes-log-cleanup-$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "清理超过 ${keep_days} 天的日志文件..."
    
    {
        echo "Notes Backend 日志清理报告"
        echo "清理时间: $(date)"
        echo "保留天数: ${keep_days} 天"
        echo "========================================"
        echo ""
        
    } > "$cleanup_report"
    
    if [ -d "$PROJECT_DIR/logs" ]; then
        echo "清理应用日志文件:" >> "$cleanup_report"
        
        find "$PROJECT_DIR/logs" -name "*.log.*" -mtime +$keep_days -type f | while read logfile; do
            local filesize=$(du -sh "$logfile" | cut -f1)
            echo "  删除: $(basename "$logfile") ($filesize)" >> "$cleanup_report"
            rm -f "$logfile"
        done
        
        find "$PROJECT_DIR/logs" -name "*.log" -size +50M -type f | while read logfile; do
            if [ ! -f "${logfile}.gz" ]; then
                local filesize=$(du -sh "$logfile" | cut -f1)
                echo "  压缩: $(basename "$logfile") ($filesize)" >> "$cleanup_report"
                gzip "$logfile"
            fi
        done
    fi
    
    echo "" >> "$cleanup_report"
    echo "清理系统日志:" >> "$cleanup_report"
    
    local journal_size_before=$(journalctl --disk-usage 2>/dev/null | awk '{print $7}' || echo "未知")
    echo "  清理前系统日志大小: $journal_size_before" >> "$cleanup_report"
    
    journalctl --vacuum-time="${keep_days}d" >> "$cleanup_report" 2>&1
    
    local journal_size_after=$(journalctl --disk-usage 2>/dev/null | awk '{print $7}' || echo "未知")
    echo "  清理后系统日志大小: $journal_size_after" >> "$cleanup_report"
    
    echo "" >> "$cleanup_report"
    echo "清理Docker容器日志:" >> "$cleanup_report"
    
    docker container prune -f >> "$cleanup_report" 2>&1
    
    log_success "日志清理完成: $cleanup_report"
}

export_logs() {
    local export_period="${1:-7}"  # 默认导出最近7天
    local export_type="${2:-all}"  # all, app, nginx, system
    local export_file="/tmp/notes-logs-export-$(date +%Y%m%d_%H%M%S).tar.gz"
    local temp_dir="/tmp/notes-logs-export-$(date +%Y%m%d_%H%M%S)"
    
    log_info "导出最近 ${export_period} 天的日志 (类型: $export_type)..."
    
    mkdir -p "$temp_dir"
    
    case "$export_type" in
        "app"|"application")
            export_application_logs "$temp_dir" "$export_period"
            ;;
        "nginx"|"proxy")
            export_nginx_logs "$temp_dir" "$export_period"
            ;;
        "system")
            export_system_logs "$temp_dir" "$export_period"
            ;;
        "all"|*)
            export_application_logs "$temp_dir" "$export_period"
            export_nginx_logs "$temp_dir" "$export_period"
            export_system_logs "$temp_dir" "$export_period"
            ;;
    esac
    
    {
        echo "Notes Backend 日志导出清单"
        echo "导出时间: $(date)"
        echo "导出周期: 最近 ${export_period} 天"
        echo "导出类型: $export_type"
        echo "========================================"
        echo ""
        echo "导出文件列表:"
        find "$temp_dir" -type f -exec ls -lh {} \; | awk '{print $9 " (" $5 ")"}'
        
    } > "$temp_dir/EXPORT_MANIFEST.txt"
    
    cd "$(dirname "$temp_dir")"
    tar -czf "$export_file" "$(basename "$temp_dir")"
    rm -rf "$temp_dir"
    
    local export_size=$(ls -lh "$export_file" | awk '{print $5}')
    log_success "日志导出完成: $export_file ($export_size)"
}

export_application_logs() {
    local export_dir="$1"
    local period="$2"
    
    mkdir -p "$export_dir/application"
    
    journalctl -u notes-backend --since "${period} days ago" > "$export_dir/application/systemd.log"
    
    if [ -d "$PROJECT_DIR/logs" ]; then
        find "$PROJECT_DIR/logs" -name "*.log" -mtime -$period -type f -exec cp {} "$export_dir/application/" \;
    fi
}

export_nginx_logs() {
    local export_dir="$1"
    local period="$2"
    
    mkdir -p "$export_dir/nginx"
    
    if docker ps | grep -q "notes-nginx"; then
        docker logs notes-nginx > "$export_dir/nginx/container.log" 2>&1
    fi
    
    if [ -d "$PROJECT_DIR/logs" ]; then
        find "$PROJECT_DIR/logs" -name "*access*.log" -mtime -$period -type f -exec cp {} "$export_dir/nginx/" \;
        find "$PROJECT_DIR/logs" -name "*error*.log" -mtime -$period -type f -exec cp {} "$export_dir/nginx/" \;
    fi
}

export_system_logs() {
    local export_dir="$1"
    local period="$2"
    
    mkdir -p "$export_dir/system"
    
    local services=("docker" "notes-nginx-http" "notes-nginx-https")
    
    for service in "${services[@]}"; do
        journalctl -u "$service" --since "${period} days ago" > "$export_dir/system/${service}.log" 2>/dev/null || true
    done
    
    journalctl --since "${period} days ago" | grep -E "(notes|docker|nginx|postgres)" > "$export_dir/system/filtered.log"
}

setup_log_alerts() {
    log_info "设置日志告警规则..."
    
    cat > /usr/local/bin/notes-log-monitor.sh << 'EOF'

ALERT_LOG="/var/log/notes-alerts.log"
PROJECT_DIR="/opt/notes-backend"

log_alert() {
    echo "[$(date)] $1" >> "$ALERT_LOG"
}

check_errors() {
    local error_count=$(journalctl -u notes-backend --since "1 hour ago" | grep -ci "error\|fatal\|panic" || echo "0")
    
    if [ "$error_count" -gt 10 ]; then
        log_alert "高错误率告警: 最近1小时内发现 $error_count 个错误"
    fi
}

check_disk_space() {
    local disk_usage=$(df -h "$PROJECT_DIR" | awk 'NR==2{print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt 90 ]; then
        log_alert "磁盘空间告警: 磁盘使用率达到 $disk_usage%"
    fi
}

check_log_size() {
    if [ -d "$PROJECT_DIR/logs" ]; then
        find "$PROJECT_DIR/logs" -name "*.log" -size +500M | while read largefile; do
            log_alert "大型日志文件告警: $(basename "$largefile") 超过500MB"
        done
    fi
}

check_service_status() {
    if ! systemctl is-active --quiet notes-backend; then
        log_alert "服务状态告警: Notes Backend 应用服务未运行"
    fi
    
    if ! systemctl is-active --quiet notes-nginx-http && ! systemctl is-active --quiet notes-nginx-https; then
        log_alert "服务状态告警: Nginx 代理服务未运行"
    fi
}

check_errors
check_disk_space
check_log_size
check_service_status
EOF

    chmod +x /usr/local/bin/notes-log-monitor.sh
    
    (
        crontab -l 2>/dev/null | grep -v "notes-log-monitor"
        echo "0 * * * * /usr/local/bin/notes-log-monitor.sh"
    ) | crontab -
    
    log_success "日志告警设置完成"
    log_info "告警日志文件: /var/log/notes-alerts.log"
    log_info "监控脚本: /usr/local/bin/notes-log-monitor.sh"
}


ensure_directories() {
    local dirs=(
        "$PROJECT_DIR"
        "$PROJECT_DIR/logs"
        "$PROJECT_DIR/uploads" 
        "$PROJECT_DIR/nginx"
        "$PROJECT_DIR/scripts"
        "$PROJECT_DIR/backup"
        "/var/www/certbot"
        "/etc/letsencrypt/live"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
        fi
    done
}

setup_ssl_certificates() {
    log_step "配置SSL证书目录"
    
    mkdir -p /var/www/certbot
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    log_info "创建临时自签名证书..."
    if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
            -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
            -subj "/C=CN/ST=State/L=City/O=Organization/OU=IT/CN=$DOMAIN" &>/dev/null
        
        chmod 644 /etc/letsencrypt/live/$DOMAIN/fullchain.pem
        chmod 600 /etc/letsencrypt/live/$DOMAIN/privkey.pem
    fi
    
    log_success "SSL证书目录配置完成"
}

fix_permissions() {
    log_info "修复文件权限..."
    
    chown -R root:root "$PROJECT_DIR" 2>/dev/null || true
    chmod -R 755 "$PROJECT_DIR" 2>/dev/null || true
    
    chmod 600 "$PROJECT_DIR/.env" 2>/dev/null || true
    chmod +x "$PROJECT_DIR/notes-backend" 2>/dev/null || true
    chmod +x "$PROJECT_DIR/scripts"/*.sh 2>/dev/null || true
    
    chmod 755 "$PROJECT_DIR/logs" 2>/dev/null || true
    chmod 755 "$PROJECT_DIR/uploads" 2>/dev/null || true
    
    log_success "文件权限修复完成"
}

verify_required_files() {
    log_info "验证必要文件..."
    
    local required_files=(
        "$PROJECT_DIR/go.mod"
        "$PROJECT_DIR/cmd/server/main.go"
        "$PROJECT_DIR/.env"
        "$PROJECT_DIR/nginx/nginx-http.conf"
        "$PROJECT_DIR/nginx/nginx-https.conf"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "缺少必要文件："
        for file in "${missing_files[@]}"; do
            echo -e "   ❌ $file"
        done
        return 1
    fi
    
    log_success "所有必要文件验证通过"
    return 0
}

emergency_fix() {
    log_info "执行应急修复..."
    
    systemctl restart docker
    sleep 5
    
    pkill -f notes-backend || true
    pkill -f nginx || true
    
    for port in 80 443 9191; do
        local pids=$(netstat -tlnp | grep ":$port " | awk '{print $7}' | cut -d'/' -f1 | grep -v '-' | sort -u)
        for pid in $pids; do
            if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    done
    
    systemctl start notes-backend
    sleep 5
    
    if systemctl is-enabled notes-nginx-https 2>/dev/null; then
        systemctl start notes-nginx-https
    else
        systemctl start notes-nginx-http
    fi
    
    log_success "应急修复完成"
}

quick_status_check() {
    local all_good=true
    
    if ! systemctl is-active --quiet notes-backend; then
        echo -e "${RED}❌ 应用服务未运行${NC}"
        all_good=false
    else
        echo -e "${GREEN}✅ 应用服务运行正常${NC}"
    fi
    
    if systemctl is-active --quiet notes-nginx-https; then
        echo -e "${GREEN}✅ HTTPS代理运行正常${NC}"
    elif systemctl is-active --quiet notes-nginx-http; then
        echo -e "${GREEN}✅ HTTP代理运行正常${NC}"
    else
        echo -e "${RED}❌ 代理服务未运行${NC}"
        all_good=false
    fi
    
    if netstat -tlnp | grep -q ":9191 "; then
        echo -e "${GREEN}✅ 应用端口监听正常${NC}"
    else
        echo -e "${RED}❌ 应用端口未监听${NC}"
        all_good=false
    fi
    
    if curl -f -s "http://127.0.0.1:9191/health" >/dev/null; then
        echo -e "${GREEN}✅ 健康检查通过${NC}"
    else
        echo -e "${RED}❌ 健康检查失败${NC}"
        all_good=false
    fi
    
    return $all_good
}

setup_environment_variables() {
    export PATH=$PATH:/usr/local/go/bin
    export GOPROXY=https://goproxy.cn,direct
    export GO111MODULE=on
    
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || true
    
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
}

final_check_and_fix() {
    log_step "执行最终检查和修复"
    
    ensure_directories
    
    setup_environment_variables
    
    fix_permissions
    
    if ! verify_required_files; then
        log_error "文件验证失败，无法继续"
        return 1
    fi
    
    if quick_status_check; then
        log_success "所有检查通过"
        return 0
    else
        log_warn "发现问题，尝试修复..."
        emergency_fix
        
        sleep 10
        
        if quick_status_check; then
            log_success "问题已修复"
            return 0
        else
            log_error "自动修复失败，需要手动干预"
            return 1
        fi
    fi
}