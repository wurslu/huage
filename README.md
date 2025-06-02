# Notes Backend

一个现代化的个人笔记管理系统后端 API，基于 Go + Gin + PostgreSQL 构建，提供完整的笔记管理、文件上传、用户认证等功能。

## ✨ 主要功能

### 🔐 用户系统

- **JWT 认证**：安全的用户身份验证
- **用户注册/登录**：完整的账户管理系统
- **权限控制**：基于角色的访问控制
- **密码安全**：Argon2 加密算法

### 📝 笔记管理

- **CRUD 操作**：创建、读取、更新、删除笔记
- **Markdown 支持**：原生支持 Markdown 格式
- **分类系统**：树形分类结构，支持多级嵌套
- **标签系统**：灵活的标签管理和筛选
- **全文搜索**：基于数据库的全文搜索功能
- **访问统计**：记录笔记浏览量和访问统计

### 📎 文件管理

- **多格式支持**：图片（JPG、PNG、GIF、WebP）和文档（PDF、Word、Excel）
- **安全上传**：文件类型验证和大小限制
- **存储配额**：用户存储空间管理
- **权限控制**：文件访问权限验证

### 🔗 分享功能

- **公开分享**：生成安全的分享链接
- **密码保护**：可选的密码保护功能
- **过期控制**：支持设置分享链接过期时间
- **访问统计**：记录分享链接访问数据

### 🛡️ 安全特性

- **CORS 配置**：跨域资源共享控制
- **限流保护**：API 请求频率限制
- **SQL 注入防护**：使用 GORM 预防 SQL 注入
- **文件安全**：上传文件类型和大小验证

## 🛠 技术栈

### 核心框架

- **Go 1.23** - 现代化的系统编程语言
- **Gin** - 高性能的 HTTP Web 框架
- **GORM** - 强大的 Go ORM 库

### 数据库

- **PostgreSQL 15** - 可靠的关系型数据库
- **Redis** - 高性能缓存（可选）

### 认证与安全

- **JWT** - JSON Web Token 认证
- **Argon2** - 密码哈希算法
- **CORS** - 跨域资源共享

### 部署与监控

- **Docker** - 容器化部署
- **Docker Compose** - 多容器编排
- **Nginx** - 反向代理和负载均衡

## 📁 项目结构

```
.
├── cmd/
│   └── server/
│       └── main.go              # 应用入口
├── internal/
│   ├── config/                  # 配置管理
│   ├── database/                # 数据库连接和迁移
│   ├── handlers/                # HTTP 处理器
│   ├── middleware/              # 中间件
│   ├── models/                  # 数据模型
│   ├── routes/                  # 路由定义
│   ├── services/                # 业务逻辑
│   └── utils/                   # 工具函数
├── pkg/
│   ├── logger/                  # 日志系统
│   └── validator/               # 验证器
├── configs/                     # 配置文件
├── scripts/                     # 部署脚本
├── nginx/                       # Nginx 配置
├── uploads/                     # 上传文件目录
├── logs/                        # 日志文件
├── backup/                      # 备份文件
├── docker-compose.yml           # Docker Compose 配置
├── Dockerfile                   # Docker 镜像构建
├── Makefile                     # 构建和部署命令
└── README.md                    # 项目文档
```

## 🚀 快速开始

### 环境要求

- Go 1.23+
- PostgreSQL 15+
- Docker & Docker Compose (可选)

### 本地开发

#### 1. 克隆项目

```bash
git clone <repository-url>
cd notes-backend
```

#### 2. 初始化项目

```bash
make init
```

这将会：

- 复制 `.env.example` 到 `.env`
- 创建必要的目录
- 下载 Go 依赖

#### 3. 配置环境变量

编辑 `.env` 文件：

```bash
# 数据库配置
DB_HOST=localhost
DB_PORT=5432
DB_USER=notes_user
DB_PASSWORD=your_secure_password
DB_NAME=notes_db

# JWT 密钥（生产环境请更换）
JWT_SECRET=your-super-secret-jwt-key-minimum-32-characters

# 服务器配置
SERVER_PORT=9191
GIN_MODE=debug

# 前端 URL
FRONTEND_BASE_URL=http://localhost:5173
```

#### 4. 启动数据库

```bash
# 使用 Docker
docker-compose up -d postgres

# 或手动安装 PostgreSQL 并创建数据库
```

#### 5. 运行开发服务器

```bash
# 普通运行
make dev

# 或使用热重载
make dev-watch
```

访问 http://localhost:9191/health 验证服务是否正常运行。

### 🐳 Docker 部署

#### 快速启动

```bash
# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f notes-backend

# 停止服务
docker-compose down
```

#### 生产环境部署

```bash
# 构建生产镜像
make docker-build

# 部署到本地 Docker
make deploy local

# 部署到远程服务器
make deploy remote
```

## ⚙️ 配置说明

### 环境变量

所有配置都可以通过环境变量覆盖，优先级：

1. 环境变量
2. `.env` 文件
3. `configs/config.yaml`
4. 默认值

### 主要配置项

- `DB_*`: 数据库连接配置
- `JWT_SECRET`: JWT 签名密钥
- `SERVER_PORT`: 服务器端口
- `GIN_MODE`: Gin 运行模式 (debug/release)
- `UPLOAD_PATH`: 文件上传路径
- `MAX_*_SIZE`: 文件大小限制
- `FRONTEND_BASE_URL`: 前端域名（用于生成分享链接）

## 📋 API 文档

### 认证相关

```
POST /api/auth/register    # 用户注册
POST /api/auth/login       # 用户登录
GET  /api/auth/me          # 获取当前用户信息
POST /api/auth/logout      # 用户登出
```

### 笔记管理

```
GET    /api/notes          # 获取笔记列表
POST   /api/notes          # 创建笔记
GET    /api/notes/:id      # 获取单个笔记
PUT    /api/notes/:id      # 更新笔记
DELETE /api/notes/:id      # 删除笔记
GET    /api/notes/stats    # 获取用户统计
```

### 分类管理

```
GET    /api/categories     # 获取分类列表
POST   /api/categories     # 创建分类
PUT    /api/categories/:id # 更新分类
DELETE /api/categories/:id # 删除分类
```

### 标签管理

```
GET    /api/tags           # 获取标签列表
POST   /api/tags           # 创建标签
PUT    /api/tags/:id       # 更新标签
DELETE /api/tags/:id       # 删除标签
```

### 文件管理

```
POST   /api/notes/:id/attachments  # 上传附件
GET    /api/notes/:id/attachments  # 获取附件列表
DELETE /api/attachments/:id        # 删除附件
GET    /api/files/:id              # 下载文件
GET    /api/user/storage           # 获取存储信息
```

### 分享功能

```
POST   /api/notes/:id/share        # 创建分享链接
GET    /api/notes/:id/share        # 获取分享信息
DELETE /api/notes/:id/share        # 删除分享链接
GET    /api/public/notes/:code     # 访问公开笔记
```

## 🔧 开发工具

### Make 命令

```bash
make help           # 显示帮助信息
make deps           # 安装依赖
make build          # 构建二进制文件
make dev            # 开发模式运行
make dev-watch      # 热重载开发
make test           # 运行测试
make test-coverage  # 测试覆盖率
make fmt            # 格式化代码
make lint           # 代码检查
make docker-build   # 构建 Docker 镜像
make docker-run     # 运行 Docker 容器
```

### 开发工具安装

```bash
make install-tools  # 安装开发工具
```

包括：

- `golangci-lint` - 代码检查工具
- `air` - 热重载工具

## 🚀 部署指南

### 生产环境部署

#### 1. 服务器准备

```bash
# 安装 Docker 和 Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### 2. 配置环境

```bash
# 复制项目到服务器
scp -r . user@server:/opt/notes/

# 配置生产环境变量
cp .env.example .env
# 编辑 .env 文件，设置生产环境配置
```

#### 3. SSL 证书设置

```bash
# 安装 Certbot 并获取证书
make ssl
```

#### 4. 启动服务

```bash
# 启动生产环境
docker-compose -f docker-compose.yml up -d

# 验证服务状态
make monitor
```

### 监控和维护

#### 健康检查

```bash
make monitor        # 运行健康检查
curl http://localhost:8080/health  # API 健康检查
```

#### 备份和恢复

```bash
make backup         # 备份数据库和文件
make restore backup/backup_file.sql.gz  # 恢复备份
```

#### 日志查看

```bash
docker-compose logs -f notes-backend    # 查看应用日志
docker-compose logs -f postgres         # 查看数据库日志
```

## 🔒 安全配置

### 生产环境安全检查

- [ ] 更改默认的 JWT 密钥
- [ ] 设置强密码的数据库用户
- [ ] 配置防火墙规则
- [ ] 启用 HTTPS
- [ ] 设置适当的 CORS 策略
- [ ] 配置速率限制
- [ ] 定期更新依赖包

### 推荐的安全实践

1. **定期备份**：设置自动备份计划
2. **监控日志**：定期检查应用和访问日志
3. **更新依赖**：定期更新 Go 依赖包
4. **访问控制**：使用防火墙限制不必要的端口访问
5. **SSL/TLS**：始终使用 HTTPS

## 🐛 故障排除

### 常见问题

#### 1. 数据库连接失败

```bash
# 检查数据库是否运行
docker-compose ps postgres

# 查看数据库日志
docker-compose logs postgres

# 检查连接配置
cat .env | grep DB_
```

#### 2. 文件上传失败

```bash
# 检查上传目录权限
ls -la uploads/

# 检查磁盘空间
df -h

# 查看应用日志
docker-compose logs notes-backend
```

#### 3. JWT 认证问题

```bash
# 检查 JWT 密钥配置
cat .env | grep JWT_SECRET

# 确保密钥长度至少 32 字符
```

## 📊 性能优化

### 数据库优化

- 合理设置连接池大小
- 添加必要的数据库索引
- 定期清理过期的访问记录

### 缓存策略

- 使用 Redis 缓存热点数据
- 实现查询结果缓存
- 配置适当的缓存过期时间

### 监控指标

- API 响应时间
- 数据库查询性能
- 文件存储使用量
- 内存和 CPU 使用率

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

**Notes Backend** - 为现代笔记应用提供强大而安全的后端支持。
