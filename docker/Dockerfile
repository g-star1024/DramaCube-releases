# 剧立方 DramaCube — Docker 一键部署版（路线 A：Linux 桌面版 + 虚拟显示 + noVNC）
#
# 用法：
#   docker run -d --name dramacube -p 3000:3000 -v dramacube-data:/data \
#     ghcr.io/g-star1024/dramacube-releases/dramacube:latest
#   浏览器打开 http://localhost:3000/ （自动全屏连接；如需手动控制用 /vnc.html）
#
# 镜像由 DramaCube-releases CI 的 docker job 构建：
#   - bundle/  由 linux job 的 dramacube-linux-v<ver>.tar.gz 解包注入（不提交到 git）
#   - /data    挂载卷：HOME 指向 /data，应用配置/数据库/图片缓存全部持久化
#   - 3000     noVNC Web 端口（内含 VNC 5900，仅本机回环，不对外暴露）
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# 体积优化（v2.7.83 起）：
#   - 中文字体由 fonts-noto-cjk（~120MB）换成 fonts-wqy-zenhei（~9MB）+ fonts-dejavu-core（Latin/UI 兜底），
#     单个 apt 层从 300MB+ 降到 ~60MB，弱网下拉取稳很多；中文渲染覆盖 GBK/GB2312/Big5/CJK。
#   - 去掉 mpv CLI 包，仅保留 libmpv2 运行库（应用用 FFI 调 libmpv 播放，不依赖 mpv 命令行）。
#   - ffmpeg 保留：NAS 封面截帧经 Process.run 调 ffmpeg 二进制，删了会丢该功能。
RUN apt-get update && apt-get install -y --no-install-recommends \
        # 虚拟显示 + VNC + Web 访问
        xvfb x11vnc novnc websockify \
        # Flutter Linux 运行时依赖（与 CI 构建机安装的 -dev 对应的运行库）
        libgtk-3-0 libmpv2 \
        libayatana-appindicator3-1 libsecret-1-0 libnotify4 \
        # NAS 封面截帧用的外部 ffmpeg（应用通过 Process.run 调用）
        ffmpeg \
        # 中文字体：文泉驿正黑（轻量）+ DejaVu（Latin/UI 兜底）
        fonts-wqy-zenhei fonts-dejavu-core \
        # PID 1 僵尸回收（Xvfb/x11vnc 子进程清理）
        tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 应用本体（CI 构建时注入）
COPY bundle/ /app/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chmod +x /app/dramacube

# 数据持久化：entrypoint 将 HOME 指向 /data
RUN mkdir -p /data
VOLUME ["/data"]

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
