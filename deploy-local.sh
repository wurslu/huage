#!/bin/bash

# ===========================
# deploy-local.sh - 本地部署脚本
# ===========================

echo "🚀 Notes Backend 本地一键部署"
echo "=================================="

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose 未安装，请先安装 Docker Compose"
    exit 1
fi

# 检查 .env 文件
if [ ! -f ".env" ]; then
    echo "📝 创建默认 .env 文件..."
    cat > .env << 'EOF'
# 数据库模式 - 本地部署
DB_MODE=local

# 本地数据库配置
LOCAL_DB_HOST=postgres
LOCAL_DB_PORT=5432
LOCAL_DB_USER=notes_user
LOCAL_DB_PASSWORD=notes_password_2024
LOCAL_DB_NAME=notes_db

# 应用配置
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production-2024
SERVER_PORT=9191
GIN_MODE=release
FRONTEND_BASE_URL=https://huage.api.withgo.cn

# Docker 配置
CONTAINER_PORT=9191
HOST_PORT=9191
EOF
    echo "✅ 已创建默认配置文件 .env"
    echo "⚠️  请编辑 .env 文件，修改 JWT_SECRET 等配置"
fi

# 创建必要目录
echo "📁 创建必要目录..."
mkdir -p uploads/users uploads/temp logs backup nginx/ssl scripts

# 创建数据库初始化脚本
if [ ! -f "scripts/init-db.sql" ]; then
    cat > scripts/init-db.sql << 'EOF'
-- 数据库初始化脚本
-- 创建扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 设置时区
SET timezone = 'Asia/Shanghai';
EOF
    echo "✅ 创建数据库初始化脚本"
fi

# 停止现有服务
echo "🛑 停止现有服务..."
docker-compose --profile local down

# 构建并启动服务
echo "🔨 构建和启动服务..."
docker-compose --profile local up -d --build

# 等待服务启动
echo "⏳ 等待服务启动..."
sleep 15

# 检查服务状态
echo "🔍 检查服务状态..."
docker-compose --profile local ps

# 检查健康状态
echo "❤️  检查应用健康状态..."
for i in {1..30}; do
    if curl -f http://localhost:9191/health >/dev/null 2>&1; then
        echo "✅ 应用启动成功！"
        break
    else
        echo "⏳ 等待应用启动... ($i/30)"
        sleep 2
    fi
done

# 显示访问信息
echo ""
echo "🎉 部署完成！"
echo "=================================="
echo "📱 应用地址: http://localhost:9191"
echo "🏥 健康检查: http://localhost:9191/health"
echo "🗄️  数据库: localhost:5432"
echo "📝 查看日志: docker-compose --profile local logs -f"
echo "🛑 停止服务: docker-compose --profile local down"
echo "=================================="

# ===========================
# deploy-vercel.sh - 使用 Vercel 数据库部署
# ===========================

cat > deploy-vercel.sh << 'EOF'
#!/bin/bash

echo "🚀 Notes Backend Vercel 数据库部署"
echo "=================================="

# 检查 .env 文件中的 Vercel 配置
if [ ! -f ".env" ]; then
    echo "❌ .env 文件不存在"
    exit 1
fi

source .env

if [ "$DB_MODE" != "vercel" ]; then
    echo "⚠️  当前 DB_MODE 不是 vercel，正在切换..."
    sed -i 's/DB_MODE=.*/DB_MODE=vercel/' .env
fi

if [ -z "$VERCEL_POSTGRES_URL" ] && [ -z "$VERCEL_POSTGRES_HOST" ]; then
    echo "❌ 未配置 Vercel 数据库信息"
    echo "请在 .env 文件中配置 VERCEL_POSTGRES_URL 或相关参数"
    exit 1
fi

echo "✅ Vercel 数据库配置检查通过"

# 只启动应用，不启动本地数据库
echo "🔨 启动应用服务..."
docker-compose up -d --build app

# 等待并检查
sleep 10
docker-compose ps

echo "🎉 Vercel 数据库模式部署完成！"
EOF

chmod +x deploy-vercel.sh

# ===========================
# switch-db.sh - 数据库切换脚本
# ===========================

cat > switch-db.sh << 'EOF'
#!/bin/bash

echo "🔄 数据库模式切换工具"
echo "=================================="
echo "1. local  - 本地 Docker PostgreSQL"
echo "2. vercel - Vercel Postgres"
echo "3. custom - 自定义数据库"
echo "=================================="

read -p "请选择数据库模式 (1-3): " choice

case $choice in
    1)
        echo "切换到本地数据库模式..."
        sed -i 's/DB_MODE=.*/DB_MODE=local/' .env
        docker-compose down
        docker-compose --profile local up -d
        echo "✅ 已切换到本地数据库"
        ;;
    2)
        echo "切换到 Vercel 数据库模式..."
        sed -i 's/DB_MODE=.*/DB_MODE=vercel/' .env
        docker-compose down
        docker-compose up -d app
        echo "✅ 已切换到 Vercel 数据库"
        ;;
    3)
        echo "切换到自定义数据库模式..."
        sed -i 's/DB_MODE=.*/DB_MODE=custom/' .env
        docker-compose down
        docker-compose up -d app
        echo "✅ 已切换到自定义数据库"
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac
EOF

chmod +x switch-db.sh

# ===========================
# manage.sh - 管理脚本
# ===========================

cat > manage.sh << 'EOF'
#!/bin/bash

echo "🛠️  Notes Backend 管理工具"
echo "=================================="
echo "1. 查看状态"
echo "2. 查看日志"
echo "3. 重启服务"
echo "4. 停止服务"
echo "5. 数据库备份"
echo "6. 数据库恢复"
echo "7. 清理数据"
echo "=================================="

read -p "请选择操作 (1-7): " choice

case $choice in
    1)
        echo "📊 服务状态:"
        docker-compose ps
        echo ""
        echo "💾 磁盘使用:"
        df -h
        echo ""
        echo "🐳 Docker 使用:"
        docker system df
        ;;
    2)
        echo "📝 查看日志:"
        docker-compose logs -f --tail=50
        ;;
    3)
        echo "🔄 重启服务..."
        docker-compose restart
        echo "✅ 服务已重启"
        ;;
    4)
        echo "🛑 停止服务..."
        docker-compose down
        echo "✅ 服务已停止"
        ;;
    5)
        echo "💾 数据库备份..."
        ./scripts/backup.sh
        ;;
    6)
        echo "📥 数据库恢复..."
        ls -la backup/
        read -p "请输入备份文件名: " backup_file
        ./scripts/restore.sh backup/$backup_file
        ;;
    7)
        echo "⚠️  这将删除所有数据！"
        read -p "确认删除所有数据？(yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            docker-compose down -v
            docker volume prune -f
            rm -rf uploads/* logs/* backup/*
            echo "✅ 数据已清理"
        else
            echo "❌ 操作已取消"
        fi
        ;;
    *)
        echo "❌ 无效选择"
        exit 1
        ;;
esac
EOF

chmod +x manage.sh

echo "✅ 所有脚本创建完成！"
echo ""
echo "🎯 快速开始："
echo "  ./deploy-local.sh     # 本地一键部署"
echo "  ./deploy-vercel.sh    # 使用 Vercel 数据库"
echo "  ./switch-db.sh        # 切换数据库模式"
echo "  ./manage.sh           # 管理工具"