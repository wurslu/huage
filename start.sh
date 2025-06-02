#!/bin/bash

# start.sh - 启动脚本

echo "==================================="
echo "Notes Backend 启动脚本"
echo "==================================="

# 检查 .env 文件是否存在
if [ ! -f ".env" ]; then
    echo "错误: .env 文件不存在"
    echo "请根据 .env.example 创建 .env 文件并配置数据库连接"
    exit 1
fi

# 检查 Go 环境
if ! command -v go &> /dev/null; then
    echo "错误: Go 未安装或不在 PATH 中"
    exit 1
fi

echo "检查 Go 版本..."
go version

# 创建必要的目录
echo "创建必要目录..."
mkdir -p uploads/users uploads/temp logs backup

# 检查数据库连接
echo "检查配置..."
source .env

if [ -n "$POSTGRES_URL" ]; then
    echo "✓ 使用 Vercel Postgres URL"
elif [ -n "$DATABASE_URL" ]; then
    echo "✓ 使用 DATABASE_URL"
elif [ -n "$POSTGRES_HOST" ] && [ -n "$POSTGRES_USER" ]; then
    echo "✓ 使用独立的数据库参数"
elif [ -n "$DB_HOST" ] && [ -n "$DB_USER" ]; then
    echo "✓ 使用传统数据库参数"
else
    echo "错误: 未找到有效的数据库配置"
    echo "请在 .env 文件中配置以下之一："
    echo "- POSTGRES_URL (推荐，用于 Vercel Postgres)"
    echo "- DATABASE_URL"
    echo "- POSTGRES_HOST, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DATABASE"
    echo "- DB_HOST, DB_USER, DB_PASSWORD, DB_NAME"
    exit 1
fi

# 下载依赖
echo "下载 Go 依赖..."
go mod tidy

if [ $? -ne 0 ]; then
    echo "错误: 依赖下载失败"
    echo "如果网络有问题，可以尝试设置代理："
    echo "export GOPROXY=https://goproxy.cn,direct"
    exit 1
fi

# 编译并运行
echo "启动应用..."
echo "服务端口: ${SERVER_PORT:-9191}"
echo "前端 URL: ${FRONTEND_BASE_URL:-https://huage.api.withgo.cn}"
echo "==================================="

go run cmd/server/main.go