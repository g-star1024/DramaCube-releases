#!/bin/sh
# 启动网关（后台）+ nginx（前台）

dramacube-gateway &
GATEWAY_PID=$!
echo "[dramacube] gateway started (pid=$GATEWAY_PID)"

# nginx（前台）
echo "[dramacube] nginx starting..."
nginx -g "daemon off;"
