#!/bin/bash
# scripts/deploy.sh - 生产环境部署脚本

set -e

echo "🚀 Notes Backend Deployment Script"
echo "=================================="

# 配置变量
PROJECT_NAME="notes-backend"
DEPLOY_USER="deploy"
DEPLOY_HOST="your-server.com"
DEPLOY_PATH="/opt/notes"
BACKUP_PATH="/opt/notes/backup"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要命令
check_dependencies() {
    log_info "Checking dependencies..."
    
    for cmd in docker docker-compose git rsync; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed"
            exit 1
        fi
    done
    
    log_info "All dependencies are available"
}

# 构建 Docker 镜像
build_image() {
    log_info "Building Docker image..."
    
    # 构建镜像
    docker build -t $PROJECT_NAME:latest .
    
    # 标记版本
    if [ ! -z "$1" ]; then
        docker tag $PROJECT_NAME:latest $PROJECT_NAME:$1
        log_info "Tagged image as $PROJECT_NAME:$1"
    fi
    
    log_info "Docker image built successfully"
}

# 备份当前部署
backup_current() {
    log_info "Creating backup..."
    
    BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)"
    
    # 备份数据库
    docker-compose exec postgres pg_dump -U notes_user notes_db > $BACKUP_PATH/db-$BACKUP_NAME.sql
    
    # 备份上传文件
    tar -czf $BACKUP_PATH/uploads-$BACKUP_NAME.tar.gz uploads/
    
    log_info "Backup created: $BACKUP_NAME"
}

# 部署到本地 Docker
deploy_local() {
    log_info "Deploying locally with Docker Compose..."
    
    # 停止现有服务
    docker-compose down
    
    # 构建并启动服务
    docker-compose up -d --build
    
    # 等待服务启动
    sleep 10
    
    # 健康检查
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        log_info "Local deployment successful!"
    else
        log_error "Local deployment failed - health check failed"
        exit 1
    fi
}

# 部署到远程服务器
deploy_remote() {
    log_info "Deploying to remote server: $DEPLOY_HOST"
    
    # 同步代码到服务器
    log_info "Syncing code to server..."
    rsync -avz --exclude='.git' --exclude='node_modules' --exclude='uploads' . $DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/
    
    # 在远程服务器执行部署
    ssh $DEPLOY_USER@$DEPLOY_HOST "cd $DEPLOY_PATH && ./scripts/remote-deploy.sh"
    
    log_info "Remote deployment completed"
}

# 远程服务器部署脚本
create_remote_deploy_script() {
    cat > scripts/remote-deploy.sh << 'EOF'
#!/bin/bash
# scripts/remote-deploy.sh - 远程服务器执行的部署脚本

set -e

echo "🔄 Executing remote deployment..."

# 备份当前数据
echo "📦 Creating backup..."
docker-compose exec postgres pg_dump -U notes_user notes_db > backup/db-$(date +%Y%m%d-%H%M%S).sql

# 停止服务
echo "🛑 Stopping services..."
docker-compose down

# 拉取最新镜像并启动
echo "🚀 Starting updated services..."
docker-compose pull
docker-compose up -d --build

# 等待服务启动
echo "⏳ Waiting for services to start..."
sleep 30

# 健康检查
echo "🏥 Performing health check..."
for i in {1..30}; do
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ Services are healthy!"
        break
    else
        echo "Waiting for services... ($i/30)"
        sleep 2
    fi
done

# 清理旧镜像
echo "🧹 Cleaning up old images..."
docker image prune -f

echo "✅ Remote deployment completed successfully!"
EOF

    chmod +x scripts/remote-deploy.sh
}

# SSL 证书设置脚本
setup_ssl() {
    log_info "Setting up SSL certificates..."
    
    cat > scripts/setup-ssl.sh << 'EOF'
#!/bin/bash
# scripts/setup-ssl.sh - SSL 证书设置

DOMAIN="your-domain.com"
EMAIL="your-email@example.com"

# 安装 Certbot
if ! command -v certbot &> /dev/null; then
    echo "Installing Certbot..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# 获取证书
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --non-interactive

# 设置自动续期
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

echo "✅ SSL setup completed!"
EOF

    chmod +x scripts/setup-ssl.sh
    log_info "SSL setup script created"
}

# 监控脚本
create_monitoring_script() {
    cat > scripts/monitor.sh << 'EOF'
#!/bin/bash
# scripts/monitor.sh - 服务监控脚本

check_service() {
    local service_name=$1
    local health_url=$2
    
    if curl -f $health_url > /dev/null 2>&1; then
        echo "✅ $service_name is healthy"
        return 0
    else
        echo "❌ $service_name is unhealthy"
        return 1
    fi
}

echo "🏥 Notes Backend Health Check - $(date)"
echo "======================================"

# 检查后端 API
check_service "Backend API" "http://localhost:8080/health"

# 检查数据库
if docker-compose exec postgres pg_isready -U notes_user -d notes_db > /dev/null 2>&1; then
    echo "✅ Database is healthy"
else
    echo "❌ Database is unhealthy"
fi

# 检查磁盘空间
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "⚠️  Disk usage is high: ${DISK_USAGE}%"
else
    echo "✅ Disk usage is normal: ${DISK_USAGE}%"
fi

# 检查内存使用
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [ $MEMORY_USAGE -gt 80 ]; then
    echo "⚠️  Memory usage is high: ${MEMORY_USAGE}%"
else
    echo "✅ Memory usage is normal: ${MEMORY_USAGE}%"
fi

echo "======================================"
EOF

    chmod +x scripts/monitor.sh
    log_info "Monitoring script created"
}

# 数据库备份脚本
create_backup_script() {
    cat > scripts/backup-db.sh << 'EOF'
#!/bin/bash
# scripts/backup-db.sh - 数据库备份脚本

set -e

BACKUP_DIR="./backup"
DATE=$(date +%Y%m%d_%H%M%S)
DB_BACKUP_FILE="$BACKUP_DIR/notes_db_$DATE.sql"
UPLOADS_BACKUP_FILE="$BACKUP_DIR/uploads_$DATE.tar.gz"

# 创建备份目录
mkdir -p $BACKUP_DIR

echo "📦 Starting backup process..."

# 备份数据库
echo "💾 Backing up database..."
docker-compose exec -T postgres pg_dump -U notes_user -d notes_db > $DB_BACKUP_FILE
gzip $DB_BACKUP_FILE
echo "✅ Database backup completed: ${DB_BACKUP_FILE}.gz"

# 备份上传文件
echo "📁 Backing up uploads..."
tar -czf $UPLOADS_BACKUP_FILE uploads/
echo "✅ Uploads backup completed: $UPLOADS_BACKUP_FILE"

# 清理旧备份 (保留30天)
echo "🧹 Cleaning old backups..."
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "✅ Backup process completed successfully!"
echo "Files created:"
echo "  - ${DB_BACKUP_FILE}.gz"
echo "  - $UPLOADS_BACKUP_FILE"
EOF

    chmod +x scripts/backup-db.sh
    log_info "Backup script created"
}

# 恢复脚本
create_restore_script() {
    cat > scripts/restore-db.sh << 'EOF'
#!/bin/bash
# scripts/restore-db.sh - 数据库恢复脚本

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_file.sql.gz>"
    echo "Available backups:"
    ls -la backup/*.sql.gz 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE=$1

if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  WARNING: This will replace the current database!"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 0
fi

echo "🔄 Restoring database from $BACKUP_FILE..."

# 解压并恢复
gunzip -c "$BACKUP_FILE" | docker-compose exec -T postgres psql -U notes_user -d notes_db

echo "✅ Database restore completed!"
EOF

    chmod +x scripts/restore-db.sh
    log_info "Restore script created"
}

# 主函数
main() {
    case "$1" in
        "local")
            check_dependencies
            backup_current
            deploy_local
            ;;
        "remote")
            check_dependencies
            create_remote_deploy_script
            deploy_remote
            ;;
        "build")
            check_dependencies
            build_image "$2"
            ;;
        "ssl")
            setup_ssl
            ;;
        "monitor")
            create_monitoring_script
            scripts/monitor.sh
            ;;
        "backup")
            create_backup_script
            scripts/backup-db.sh
            ;;
        "restore")
            create_restore_script
            scripts/restore-db.sh "$2"
            ;;
        "init")
            log_info "Initializing deployment scripts..."
            create_remote_deploy_script
            setup_ssl
            create_monitoring_script
            create_backup_script
            create_restore_script
            log_info "All deployment scripts created!"
            ;;
        *)
            echo "Usage: $0 {local|remote|build|ssl|monitor|backup|restore|init}"
            echo ""
            echo "Commands:"
            echo "  local     - Deploy locally with Docker Compose"
            echo "  remote    - Deploy to remote server"
            echo "  build     - Build Docker image"
            echo "  ssl       - Setup SSL certificates"
            echo "  monitor   - Run health checks"
            echo "  backup    - Backup database and files"
            echo "  restore   - Restore from backup"
            echo "  init      - Initialize all deployment scripts"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"