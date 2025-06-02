# Dockerfile - 优化版本
FROM golang:1.24-alpine AS builder

# 设置工作目录
WORKDIR /app

# 安装必要的包和工具
RUN apk add --no-cache \
    git \
    ca-certificates \
    tzdata \
    wget

# 设置 Go 代理（解决网络问题）
ENV GOPROXY=https://goproxy.cn,direct
ENV GO111MODULE=on
ENV CGO_ENABLED=0
ENV GOOS=linux

# 复制 go mod 文件
COPY go.mod go.sum ./

# 下载依赖
RUN go mod download && go mod verify

# 复制源码
COPY . .

# 构建应用
RUN go build -a -installsuffix cgo -ldflags="-w -s" -o main cmd/server/main.go

# 运行阶段 - 使用更小的基础镜像
FROM alpine:latest

# 安装必要的包
RUN apk --no-cache add \
    ca-certificates \
    tzdata \
    wget \
    curl \
    postgresql-client && \
    rm -rf /var/cache/apk/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

# 创建非 root 用户
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# 从构建阶段复制二进制文件和配置
COPY --from=builder /app/main .
COPY --from=builder /app/configs ./configs
COPY --chown=appuser:appgroup --from=builder /app/configs ./configs

# 创建必要的目录并设置权限
RUN mkdir -p uploads logs backup && \
    chown -R appuser:appgroup /app

# 切换到非 root 用户
USER appuser

# 暴露端口
EXPOSE 9191

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:9191/health || exit 1

# 运行应用
CMD ["./main"]