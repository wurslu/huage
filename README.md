# 虚假的文档

现代化的个人笔记管理系统后端 API，基于 **Go + Gin + Vercel Postgres** 构建，使用 **Docker** 部署到 **CentOS** 服务器。

## ✨ 核心特性

### 🔐 用户系统

- JWT 认证，Argon2 密码加密
- 用户注册/登录，权限控制

### 📝 笔记管理

- CRUD 操作，Markdown 支持
- 树形分类系统，灵活标签管理
- 全文搜索，访问统计

### 📎 文件管理

- 图片/文档上传，存储配额管理
- 安全验证，权限控制

### 🔗 分享功能

- 公开分享链接，密码保护
- 过期控制，访问统计

## 🛠 技术栈

- **后端**: Go 1.23 + Gin + GORM
- **数据库**: Vercel Postgres (云数据库)
- **部署**: Docker + Nginx + CentOS
- **认证**: JWT + Argon2

## 📁 项目结构

```
notes-backend/
├── cmd/server/          # 应用入口
├── internal/            # 内部包
│   ├── config/         # 配置管理
│   ├── database/       # 数据库连接
│   ├── handlers/       # HTTP 处理器
│   ├── middleware/     # 中间件
│   ├── models/         # 数据模型
│   ├── routes/         # 路由定义
│   ├── services/       # 业务逻辑
│   └── utils/          # 工具函数
├── nginx/              # Nginx 配置
├── docker-compose.yml  # Docker 编排
├── Dockerfile          # 容器构建
└── deploy.sh          # CentOS 部署脚本
```

## 🚀 快速部署

### 1. 准备 Vercel 数据库

1. 访问 [Vercel Dashboard](https://vercel.com/dashboard)
2. 创建新的 Postgres 数据库
3. 复制连接字符串，格式如：
   ```
   postgresql://user:password@host:5432/database?sslmode=require
   ```

### 2. CentOS 服务器自动安装

在 CentOS 服务器上运行：

```bash
# 下载部署脚本
curl -O https://raw.githubusercontent.com/your-repo/notes-backend/main/deploy.sh

# 运行自动安装
chmod +x deploy.sh
sudo ./deploy.sh
```

脚本会自动安装：

- Docker & Docker Compose
- 防火墙配置
- 项目目录结构
- SSL 证书工具
- 系统服务

### 3. 配置环境变量

编辑配置文件：

```bash
cd /opt/notes-backend
nano .env
```

填入配置：

```bash
# 数据库 (从 Vercel 复制)
VERCEL_POSTGRES_URL="postgresql://user:password@host:5432/database?sslmode=require"

# 应用配置
JWT_SECRET="your-super-secret-jwt-key-change-this"
FRONTEND_BASE_URL="https://huage.api.withgo.cn"
```

### 4. 获取 SSL 证书

```bash
# 自动获取 Let's Encrypt 证书
certbot --nginx -d huage.api.withgo.cn
```

### 5. 启动服务

```bash
cd /opt/notes-backend
./start.sh
```

## 🔧 管理命令

```bash
# 服务管理
./start.sh      # 启动服务
./stop.sh       # 停止服务
./restart.sh    # 重启服务
./logs.sh       # 查看日志

# 系统服务
systemctl start notes-backend     # 启动
systemctl stop notes-backend      # 停止
systemctl status notes-backend    # 状态
```

## 📋 API 文档

### 认证接口

```
POST /api/auth/register    # 用户注册
POST /api/auth/login       # 用户登录
GET  /api/auth/me          # 获取用户信息
```

### 笔记管理

```
GET    /api/notes          # 获取笔记列表
POST   /api/notes          # 创建笔记
GET    /api/notes/:id      # 获取单个笔记
PUT    /api/notes/:id      # 更新笔记
DELETE /api/notes/:id      # 删除笔记
```

### 分类标签

```
GET    /api/categories     # 获取分类
POST   /api/categories     # 创建分类
GET    /api/tags           # 获取标签
POST   /api/tags           # 创建标签
```

### 文件管理

```
POST   /api/notes/:id/attachments  # 上传文件
GET    /api/files/:id              # 下载文件
DELETE /api/attachments/:id        # 删除文件
```

### 分享功能

```
POST   /api/notes/:id/share        # 创建分享
GET    /api/public/notes/:code     # 访问分享
DELETE /api/notes/:id/share        # 删除分享
```

## 🔒 安全配置

### 生产环境检查清单

- [ ] 更改默认 JWT 密钥
- [ ] 配置 HTTPS 证书
- [ ] 设置防火墙规则
- [ ] 配置适当的 CORS 策略
- [ ] 启用访问日志监控

### 推荐安全设置

```bash
# 防火墙配置
firewall-cmd --permanent --add-port=80/tcp     # HTTP
firewall-cmd --permanent --add-port=443/tcp    # HTTPS
firewall-cmd --permanent --add-port=22/tcp     # SSH
firewall-cmd --reload
```

## 📊 监控和维护

### 健康检查

```bash
# 应用健康状态
curl https://huage.api.withgo.cn/health

# 容器状态
docker ps

# 服务状态
systemctl status notes-backend
```

### 日志管理

```bash
# 应用日志
docker-compose logs -f app

# Nginx 日志
docker-compose logs -f nginx

# 系统日志
tail -f /var/log/messages
```

### 更新部署

```bash
# 拉取最新镜像并重启
cd /opt/notes-backend
docker-compose pull
./restart.sh
```

## 🐛 故障排除

### 常见问题

**数据库连接失败**

```bash
# 检查连接字符串
echo $VERCEL_POSTGRES_URL

# 测试连接
docker-compose logs app | grep database
```

**端口被占用**

```bash
# 查看端口占用
netstat -tlnp | grep 9191

# 释放端口
systemctl stop notes-backend
```

**SSL 证书问题**

```bash
# 检查证书文件
ls -la /opt/notes-backend/nginx/ssl/

# 重新获取证书
certbot --nginx -d huage.api.withgo.cn
```

## 🔄 备份策略

由于使用 Vercel Postgres，数据库会自动备份。文件备份：

```bash
# 备份上传文件
tar -czf uploads-backup-$(date +%Y%m%d).tar.gz /opt/notes-backend/uploads/

# 定期备份脚本
echo "0 2 * * * tar -czf /backup/uploads-\$(date +\%Y\%m\%d).tar.gz /opt/notes-backend/uploads/" | crontab -
```

## 🤝 开发指南

### 本地开发

```bash
# 克隆项目
git clone <repository>
cd notes-backend

# 配置环境
cp .env.example .env
# 编辑 .env 填入 Vercel 数据库信息

# 运行
go run cmd/server/main.go
```

### 构建镜像

```bash
# 构建 Docker 镜像
docker build -t notes-backend .

# 推送到镜像仓库
docker tag notes-backend your-registry/notes-backend:latest
docker push your-registry/notes-backend:latest
```

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

**Notes Backend** - 简单、安全、高效的笔记管理系统后端
