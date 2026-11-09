#!/usr/bin/env bash
# 剧立方 Docker 容器入口：虚拟显示 → VNC → noVNC Web → 应用本体
set -e

# ---- 数据持久化 ----
# HOME 指向挂载卷 /data：path_provider 的 XDG 路径（应用支持目录/配置/缓存/
# drift 数据库/AppLog 日志）全部落在 volume 内，容器重建不丢数据。
export HOME=/data
mkdir -p "$HOME"

# ---- 虚拟显示 ----
export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
mkdir -p /tmp/.X11-unix

Xvfb :99 -screen 0 1280x720x24 -nolisten tcp &
XVFB_PID=$!

# 等 X server 就绪（最多 10s）
for i in $(seq 1 20); do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.5
done
echo "[entrypoint] Xvfb 已就绪 (pid=$XVFB_PID, display=:99, 1280x720)"

# ---- VNC 服务（仅本机回环，经由 noVNC 对外）----
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -quiet &
echo "[entrypoint] x11vnc 已启动 (:99 → :5900)"

# ---- noVNC Web（对外唯一端口 3000）----
websockify --web /usr/share/novnc 3000 localhost:5900 &
echo "[entrypoint] noVNC 已启动 → http://localhost:3000/vnc.html"

# ---- 应用本体 ----
cd /app
echo "[entrypoint] 启动剧立方 /app/dramacube"
exec ./dramacube
