FROM golang:1.23-bullseye AS builder

WORKDIR /app

# 设置 Go 代理
ENV GOPROXY=https://goproxy.cn,direct
ENV GO111MODULE=on
ENV CGO_ENABLED=0

# 复制依赖文件
COPY go.mod go.sum ./

# 下载依赖
RUN go mod download

# 复制源码
COPY . .

# 构建应用
RUN go build -ldflags="-w -s" -o main cmd/server/main.go

# 运行阶段 - 使用 Debian slim
FROM debian:bullseye-slim

# 更新包列表并安装必要工具
RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    curl \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建应用用户
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# 复制二进制文件
COPY --from=builder /app/main .
COPY --chown=appuser:appgroup configs ./configs

# 创建目录
RUN mkdir -p uploads logs backup && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 9191

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:9191/health || exit 1

CMD ["./main"]