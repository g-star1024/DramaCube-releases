# 剧立方 DramaCube — Docker 本地部署

在 NAS / 服务器 / 树莓派上一键部署剧立方 Web 版。

## 快速开始

```bash
cd apps/flutter

# 方式 1：docker-compose（推荐）
docker compose up -d

# 方式 2：纯 Docker
docker build -t dramacube .
docker run -d -p 8080:80 -p 8787:8787 \
  -v dramacube-data:/app/data \
  --name dramacube \
  dramacube
```

## 访问

| 入口 | 地址 |
|---|---|
| Web UI | http://localhost:8080 |
| 网关健康检查 | http://localhost:8787/api/health |

局域网内其他设备访问：`http://<服务器IP>:8080`

## NAS 目录挂载（可选）

如果要用「本机目录」类型资源库，把 NAS 目录挂进容器：

```yaml
# docker-compose.yml
volumes:
  - /path/to/your/nas/movies:/mnt/nas/movies:ro
```

然后在 App 里添加资源库，类型选「本机目录」，路径填 `/mnt/nas/movies`。

## 架构

```
┌─────────────────────────────────────┐
│           nginx :80                 │
│  ┌─────────────┐  ┌──────────────┐  │
│  │ Flutter Web │  │ /api → :8787 │  │
│  │  (静态文件)  │  │  Dart 网关    │  │
│  └─────────────┘  └──────────────┘  │
│                                     │
│  Dart 网关 :8787                    │
│  ├─ /api/tvbox/*  视频源解析        │
│  ├─ /api/live/*   直播源/频道       │
│  ├─ /api/play     直链代理          │
│  ├─ /api/nas/*    WebDAV/挂载      │
│  └─ /api/stream   无预置解析        │
└─────────────────────────────────────┘
```

## 资源占用

- 内存：~128MB（空载）/ ~256MB（播放中）
- CPU：几乎为 0（nginx + Dart 都是轻量服务）
- 磁盘：镜像 ~200MB，数据卷按需

树莓派 4B 可流畅运行。

## 更新

```bash
git pull
docker compose build --no-cache
docker compose up -d
```

## 数据备份

```bash
# 备份数据卷
docker run --rm -v dramacube-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/dramacube-backup-$(date +%Y%m%d).tar.gz -C /data .
```
