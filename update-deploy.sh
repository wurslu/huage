#!/bin/bash

# 自动化部署脚本 - deploy.sh
set -e

echo "🚀 开始部署 Notes 后端服务..."

# 配置变量
CONTAINER_NAME="notes-backend"
IMAGE_NAME="notes-backend"
NETWORK_NAME="notes-network"
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"

# 1. 备份当前版本
echo "📦 备份当前版本..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker commit $CONTAINER_NAME $IMAGE_NAME:backup-$(date +%Y%m%d-%H%M%S)
    echo "✅ 备份完成"
fi

# 2. 更新代码
echo "📥 更新代码..."
if [ -d ".git" ]; then
    git pull origin main
    echo "✅ Git 更新完成"
else
    echo "⚠️  请手动更新代码文件"
fi

# 3. 停止现有容器
echo "⏹️  停止现有容器..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker stop $CONTAINER_NAME
    echo "✅ 容器已停止"
fi

if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
    docker rm $CONTAINER_NAME
    echo "✅ 容器已删除"
fi

# 4. 构建新镜像
echo "🔨 构建新镜像..."
docker build -t $IMAGE_NAME .
echo "✅ 镜像构建完成"

# 5. 创建必要目录
echo "📁 创建必要目录..."
mkdir -p uploads/{users,temp} logs backup
chmod -R 755 uploads/ logs/ backup/
echo "✅ 目录创建完成"

# 6. 启动新容器
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
  -e FRONTEND_BASE_URL=https://huage.api.xiaohua.tech \
  -p 127.0.0.1:9191:9191 \
  -v $(pwd)/uploads:/app/uploads \
  -v $(pwd)/logs:/app/logs \
  notes-backend

echo "✅ 新容器已启动"

# 7. 等待服务启动
echo "⏳ 等待服务启动..."
sleep 10

# 8. 健康检查
echo "🏥 进行健康检查..."
for i in {1..30}; do
    if curl -f http://127.0.0.1:9191/health > /dev/null 2>&1; then
        echo "✅ 服务启动成功！"
        break
    fi
    echo "等待服务启动... ($i/30)"
    sleep 2
done

# 9. 检查容器状态
echo "📊 检查容器状态..."
docker ps | grep $CONTAINER_NAME

# 10. 显示日志
echo "📝 最近日志："
docker logs $CONTAINER_NAME --tail 10

echo "🎉 部署完成！"
echo "🌐 访问地址：https://huage.api.xiaohua.tech/health"