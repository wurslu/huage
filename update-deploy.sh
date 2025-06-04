#!/bin/bash

set -e

echo "🚀 开始部署 Notes 后端服务..."

CONTAINER_NAME="notes-backend"
IMAGE_NAME="notes-backend"

echo "📦 备份当前版本..."
if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker commit $CONTAINER_NAME $IMAGE_NAME:backup-$(date +%Y%m%d-%H%M%S)
    echo "✅ 备份完成"
fi

echo "⏹️ 停止现有容器..."
docker-compose down || true

echo "🔨 构建新镜像..."
docker-compose build --no-cache

echo "📁 创建必要目录..."
mkdir -p uploads/{users,temp} logs backup
chmod -R 755 uploads/ logs/ backup/

echo "🔄 启动服务..."
# 使用生产环境配置
cp .env.production .env
docker-compose up -d

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

if [ "$health_check_passed" = true ]; then
    echo "🎉 部署完成！"
    echo "🌐 服务地址：https://xiaohua.tech"
    echo "🔧 健康检查：http://127.0.0.1:9191/health"
else
    echo "❌ 部署失败，请检查日志"
    docker-compose logs
    exit 1
fi