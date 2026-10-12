#!/bin/sh
# 启动 Dart 网关（后台）+ nginx（前台）

# Dart 网关（TVBox 解析 / m3u8 代理 / WebDAV / 直播源）
cd /app
dart pub get --offline 2>/dev/null || true
dart run /app/gateway/gateway_server.dart &
GATEWAY_PID=$!

echo "[dramacube] gateway started (pid=$GATEWAY_PID)"

# nginx（前台）
echo "[dramacube] nginx starting..."
nginx -g "daemon off;"
