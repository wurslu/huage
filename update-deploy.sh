#!/bin/bash

set -e

echo "🚀 开始部署 Notes 后端服务..."

CONTAINER_NAME="notes-backend"
IMAGE_NAME="notes-backend"
NETWORK_NAME="notes-network"
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"

echo "📦 备份当前版本..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker commit $CONTAINER_NAME $IMAGE_NAME:backup-$(date +%Y%m%d-%H%M%S)
    echo "✅ 备份完成"
fi

echo "📥 更新代码..."
if [ -d ".git" ]; then
    echo "💾 备份配置文件..."
    cp .env .env.backup.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    cp configs/config.yaml configs/config.yaml.backup.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d-%H%M%S) 2>/dev/null || true
    
    echo "🔄 处理本地修改..."
    git stash push -m "自动部署备份-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    
    echo "⬇️ 拉取最新代码..."
    git pull origin master
    
    echo "🔧 恢复生产配置..."
    latest_env_backup=$(ls -t .env.backup.* 2>/dev/null | head -1)
    latest_config_backup=$(ls -t configs/config.yaml.backup.* 2>/dev/null | head -1)
    latest_compose_backup=$(ls -t docker-compose.yml.backup.* 2>/dev/null | head -1)
    
    [ -n "$latest_env_backup" ] && cp "$latest_env_backup" .env && echo "✅ 恢复 .env 配置"
    [ -n "$latest_config_backup" ] && cp "$latest_config_backup" configs/config.yaml && echo "✅ 恢复 config.yaml 配置"
    
    echo "✅ Git 更新完成"
else
    echo "⚠️  请手动更新代码文件"
fi

echo "⏹️  停止现有容器..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker stop $CONTAINER_NAME
    echo "✅ 容器已停止"
fi

if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
    docker rm $CONTAINER_NAME
    echo "✅ 容器已删除"
fi

echo "🧹 清理旧镜像..."
docker image prune -f > /dev/null 2>&1 || true

echo "🔨 构建新镜像..."
docker build -t $IMAGE_NAME . --no-cache
echo "✅ 镜像构建完成"

echo "📁 创建必要目录..."
mkdir -p uploads/{users,temp} logs backup
chmod -R 755 uploads/ logs/ backup/
echo "✅ 目录创建完成"

echo "🔄 启动新容器..."
docker run -d \
  --name $CONTAINER_NAME \
  --network $NETWORK_NAME \
  --restart unless-stopped \
  -e DB_MODE=local \
  -e LOCAL_DB_HOST=notes-postgres \
  -e LOCAL_DB_PORT=5432 \
  -e LOCAL_DB_USER=notes_user \
  -e LOCAL_DB_PASSWORD=notes_password_2024 \
  -e LOCAL_DB_NAME=notes_db \
  -e JWT_SECRET=your-super-secret-jwt-key-change-this-2024 \
  -e SERVER_PORT=9191 \
  -e GIN_MODE=release \
  -e FRONTEND_BASE_URL=https://www.xiaohua.tech \
  -p 127.0.0.1:9191:9191 \
  -v $(pwd)/uploads:/app/uploads \
  -v $(pwd)/logs:/app/logs \
  notes-backend

echo "✅ 新容器已启动"

echo "⏳ 等待服务启动..."
sleep 15

echo "🏥 进行健康检查..."
health_check_passed=false
for i in {1..30}; do
    if curl -f http://127.0.0.1:9191/health > /dev/null 2>&1; then
        echo "✅ 服务启动成功！"
        health_check_passed=true
        break
    fi
    echo "等待服务启动... ($i/30)"
    sleep 3
done

echo "📊 检查容器状态..."
docker ps | grep $CONTAINER_NAME || echo "⚠️ 容器未找到"

echo "📝 最近日志："
docker logs $CONTAINER_NAME --tail 15

if [ "$health_check_passed" = true ]; then
    echo ""
    echo "🎉 部署完成！"
    echo "🌐 前端访问地址：https://www.xiaohua.tech"
    echo "🔧 后端健康检查：https://huage.api.xiaohua.tech/health"
    echo "📊 容器状态：$(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep $CONTAINER_NAME)"
else
    echo ""
    echo "❌ 部署可能有问题，服务健康检查失败"
    echo "🔍 请检查日志："
    echo "   docker logs $CONTAINER_NAME"
    echo "🔧 手动测试命令："
    echo "   curl http://127.0.0.1:9191/health"
    exit 1
fi

echo "🧹 清理旧备份文件..."
find . -name "*.backup.*" -type f -printf '%T@ %p\n' | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs rm -f 2>/dev/null || true
echo "✅ 清理完成"