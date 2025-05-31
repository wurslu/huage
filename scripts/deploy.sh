# scripts/deploy.sh
#!/bin/bash

# 部署脚本
set -e

echo "开始部署 Notes 应用..."

# 检查 Docker 和 Docker Compose
if ! command -v docker &> /dev/null; then
    echo "错误: Docker 未安装"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "错误: Docker Compose 未安装"
    exit 1
fi

# 停止现有服务
echo "停止现有服务..."
docker-compose down

# 拉取最新代码（如果是从 Git 部署）
# git pull origin main

# 构建和启动服务
echo "构建和启动服务..."
docker-compose up -d --build

# 等待服务启动
echo "等待服务启动..."
sleep 10

# 检查服务状态
echo "检查服务状态..."
docker-compose ps

# 检查应用健康状态
echo "检查应用健康状态..."
for i in {1..30}; do
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        echo "应用启动成功！"
        break
    else
        echo "等待应用启动... ($i/30)"
        sleep 2
    fi
done

# 显示日志
echo "显示最近的日志:"
docker-compose logs --tail=50 app

echo "部署完成！"
echo "应用地址: http://localhost:8080"
echo "健康检查: http://localhost:8080/health"

---

# scripts/restore.sh
#!/bin/bash

# 数据库恢复脚本
set -e

if [ $# -eq 0 ]; then
    echo "用法: $0 <backup_file.sql.gz>"
    echo "示例: $0 ./backup/notes_20250531_120000.sql.gz"
    exit 1
fi

BACKUP_FILE=$1

if [ ! -f "$BACKUP_FILE" ]; then
    echo "错误: 备份文件不存在: $BACKUP_FILE"
    exit 1
fi

# 配置
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-notes_user}
DB_PASSWORD=${DB_PASSWORD:-notes_password}
DB_NAME=${DB_NAME:-notes_db}

echo "警告: 此操作将覆盖现有数据库!"
read -p "确定要继续吗? (y/N): " confirm

if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "操作已取消"
    exit 0
fi

echo "开始恢复数据库..."

# 解压并恢复
if [[ $BACKUP_FILE == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | PGPASSWORD=$DB_PASSWORD psql \
      -h $DB_HOST \
      -p $DB_PORT \
      -U $DB_USER \
      -d $DB_NAME
else
    PGPASSWORD=$DB_PASSWORD psql \
      -h $DB_HOST \
      -p $DB_PORT \
      -U $DB_USER \
      -d $DB_NAME \
      < "$BACKUP_FILE"
fi

echo "数据库恢复完成!"