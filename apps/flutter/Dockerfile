# 剧立方 DramaCube — Flutter 全平台 Docker 部署
#
# 架构：
#   阶段 1（gateway-builder）：dart:stable 编译网关 AOT 可执行文件
#   阶段 2（runtime）：nginx 托管本地构建的 Web 产物 + 网关可执行文件
#
# 前置：先在本地构建 Web 产物
#   flutter build web --release
#
# 用法：
#   docker build -t dramacube .
#   docker run -p 8080:80 -p 8787:8787 dramacube
#
# 或 docker-compose：
#   docker compose up -d

# ============================================================
# 阶段 1：编译网关 AOT 可执行文件
# ============================================================
FROM dart:stable AS gateway-builder

WORKDIR /app

# 依赖缓存层（网关独立 pubspec，不含 Flutter 依赖）
COPY docker/gateway-pubspec.yaml pubspec.yaml
RUN dart pub get

# 编译网关（只编译网关入口，不含 Flutter UI 依赖）
COPY lib/core/gateway/ lib/core/gateway/
COPY lib/core/models/ lib/core/models/
RUN dart compile exe lib/core/gateway/main.dart -o /app/gateway-bin

# ============================================================
# 阶段 2：运行时（nginx + 网关可执行文件）
# ============================================================
FROM debian:stable-slim

# 安装 nginx + ca-certificates（网关 HTTPS 请求需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 本地构建的 Web 静态文件
COPY build/web /usr/share/nginx/html

# 网关可执行文件
COPY --from=gateway-builder /app/gateway-bin /usr/local/bin/dramacube-gateway

# nginx 配置：Web 静态 + /api 反代到网关
COPY docker/nginx.conf /etc/nginx/sites-enabled/default

# 启动脚本
COPY docker/start.sh /start.sh
RUN chmod +x /start.sh /usr/local/bin/dramacube-gateway

EXPOSE 80 8787

CMD ["/start.sh"]
