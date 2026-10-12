# 剧立方 DramaCube — Flutter 全平台 Docker 部署
#
# 架构：
#   阶段 1（builder）：Flutter SDK 构建 Web 产物
#   阶段 2（runtime）：nginx 托管 Web 静态文件 + Dart 网关（API 代理）
#
# 用法：
#   docker build -t dramacube .
#   docker run -p 8080:80 -p 8787:8787 dramacube
#
# 或 docker-compose：
#   docker compose up -d

# ============================================================
# 阶段 1：构建 Flutter Web
# ============================================================
FROM ghcr.io/cirruslabs/flutter:3.35.4 AS builder

WORKDIR /app

# 依赖缓存层
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# 构建 Web（release）
COPY . .
RUN flutter build web --release --web-renderer canvaskit

# ============================================================
# 阶段 2：运行时（nginx + Dart 网关）
# ============================================================
FROM nginx:alpine

# 安装 Dart 运行时（跑网关）
RUN apk add --no-cache dart

# Web 静态文件
COPY --from=builder /app/build/web /usr/share/nginx/html

# 网关源码（Dart 单文件，shelf 服务）
COPY lib/core/gateway/ /app/gateway/
COPY pubspec.yaml /app/

# nginx 配置：Web 静态 + /api 反代到 Dart 网关
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# 启动脚本：先起 Dart 网关，再起 nginx
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80 8787

CMD ["/start.sh"]
