#!/usr/bin/env bash
# 剧立方 Docker 容器入口：虚拟显示 → VNC → noVNC Web → 应用本体
set -e

# ---- 数据持久化 ----
# HOME 指向挂载卷 /data：path_provider 的 XDG 路径（应用支持目录/配置/缓存/
# drift 数据库/AppLog 日志）全部落在 volume 内，容器重建不丢数据。
export HOME=/data
# XDG 基础目录：path_provider 在 Linux 上依赖这些解析应用目录，否则抛
# MissingPlatformDirectoryException，导致 drift 数据库 / 下载记录等无法持久化。
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$HOME/.runtime"
export XDG_DOCUMENTS_DIR="$HOME/Documents"
export XDG_DOWNLOAD_DIR="$HOME/Downloads"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
         "$XDG_RUNTIME_DIR" "$XDG_DOCUMENTS_DIR" "$XDG_DOWNLOAD_DIR" \
         "$XDG_DATA_HOME/DramaCube/logs"
# path_provider 的 xdg_directories 优先读取 user-dirs.dirs；容器无桌面环境，需显式生成，
# 否则即便设了 XDG_* 环境变量仍会 MissingPlatform。
cat > "$XDG_CONFIG_HOME/user-dirs.dirs" <<'UDL'
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
UDL

# ---- 虚拟显示 ----
# 默认 1920x1080（16:9，适配 NAS 接电视/大屏）；配合 noVNC ?resize=scale 缩放填充视口。
export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
mkdir -p /tmp/.X11-unix

Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp &
XVFB_PID=$!

# 等 X server 就绪（最多 10s）
for i in $(seq 1 20); do
  [ -S /tmp/.X11-unix/X99 ] && break
  sleep 0.5
done
echo "[entrypoint] Xvfb 已就绪 (pid=$XVFB_PID, display=:99, 1920x1080)"

# ---- VNC 服务（仅本机回环，经由 noVNC 对外）----
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -quiet &
echo "[entrypoint] x11vnc 已启动 (:99 → :5900)"

# ---- noVNC Web（对外唯一端口 3000）----
# 根路径 / 直接重定向到「自动连接 + 缩放填充」页，避免目录列表 / 手动 Connect / 扩展报错。
cat > /usr/share/novnc/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=vnc_lite.html?autoconnect=true&resize=scale">
  <title>剧立方 DramaCube</title>
</head>
<body></body>
</html>
EOF
websockify --web /usr/share/novnc 3000 localhost:5900 &
echo "[entrypoint] noVNC 已启动 → http://localhost:3000/ （自动全屏连接）"

# ---- 应用本体 ----
cd /app
echo "[entrypoint] 启动剧立方 /app/dramacube"
exec ./dramacube
