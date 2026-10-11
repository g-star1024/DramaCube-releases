# 剧立方 DramaCube Flutter 全平台架构

> 代码仓库：私有仓库（同 macOS 版 monorepo `hongguo-desktop/apps/flutter`）
> 软件发布：公开仓库（GitHub Releases）
> 优先级：Windows → Linux → Android → Android TV → Docker

## 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| UI 框架 | Flutter 3.x | 一套 Dart 代码全平台 |
| 播放器内核 | media_kit (libmpv) | 与 macOS 版 mpv 内核体验一致，H.265/杜比视界/ASS 字幕全支持 |
| 本地网关 | Dart 重写（shelf） | TVBox 解析 / m3u8 代理 / WebDAV，逻辑对齐 Swift 版 HongguoGatewayCore |
| 状态管理 | Riverpod | 编译时安全、可测试 |
| 本地存储 | drift (SQLite) | 收藏/历史/进度，对齐 macOS 版 SwiftData |
| 设置存储 | shared_preferences | 对齐 macOS 版 UserDefaults |
| 网络 | dio | 直连源站 + 网关代理双通道 |

## 目录结构（monorepo）

```
hongguo-desktop/
├── Sources/                    # macOS Swift 原生（现有）
├── apps/
│   └── flutter/                # Flutter 全平台（本目录）
│       ├── lib/
│       │   ├── main.dart
│       │   ├── app/            # 应用入口/路由/主题
│       │   ├── core/           # 网关/存储/网络/模型
│       │   │   ├── gateway/    # Dart 网关（shelf）
│       │   │   ├── db/         # drift 数据库
│       │   │   └── models/     # 数据模型（对齐 Swift HongguoCore）
│       │   ├── features/       # 业务模块（对齐 macOS 版 Features）
│       │   │   ├── catalog/    # 视频源浏览
│       │   │   ├── live/       # 电视直播
│       │   │   ├── nas/        # 资源库
│       │   │   ├── player/     # 播放器（media_kit）
│       │   │   ├── library/    # 收藏/历史
│       │   │   └── settings/   # 设置中心
│       │   └── l10n/           # 国际化（简体中文默认）
│       ├── windows/            # Windows 平台配置
│       ├── linux/              # Linux 平台配置
│       ├── android/            # Android 平台配置
│       ├── web/                # Docker 部署用 Flutter Web
│       ├── pubspec.yaml
│       └── ARCHITECTURE.md     # 本文档
└── Scripts/                    # 打包脚本
```

## 核心设计决策

### 1. 播放器：media_kit 全平台统一

- Windows/Linux/Android 全走 media_kit 的 libmpv 后端，与 macOS 版 mpv 内核体验一致
- Android TV 用 media_kit + Android TV 原生遥控器焦点导航（FocusNode / D-pad）
- Docker 部署的 Flutter Web 版降级用 video.js / hls.js（浏览器解码能力受限，H.265/杜比视界不支持——本地部署场景可接受）

### 2. 网关：Dart 重写，逻辑对齐 Swift 版

Swift 版 HongguoGatewayCore 的核心端点：
- `GET /api/health` — 健康检查
- `GET /api/tvbox/sites` — TVBox 站点列表
- `GET /api/tvbox/list?site=&pg=&t=` — 站点列表（分类/分页）
- `GET /api/tvbox/detail?site=&id=` — 剧集详情
- `GET /api/tvbox/search?site=&wd=` — 站点搜索
- `GET /api/tvbox/import?url=` — 订阅导入
- `GET /api/tvbox/test?site=` — 连通性测试（首页+搜索双测）
- `GET /api/live/sources` / `GET /api/live/channels?source=` — 直播源/频道
- `GET /api/live/stream?url=` — m3u8 代理（重写分片走本网关，锁大陆 IP 绕 403）
- `GET /api/play?url=` — 直链代理（剥离 Referer + Range 透传）
- `GET /api/stream/<sid>/<vid>` — 无预置直链即时解析
- `GET /api/nas/list` / `GET /api/nas/scan` — NAS 资源库（WebDAV/挂载）
- `GET /api/nas/cover` — NAS 封面（首帧截图）

Dart 重写用 shelf 包，逻辑 1:1 对齐，保证各平台行为一致。

### 3. 数据模型对齐

| macOS (Swift) | Flutter (Dart) | 说明 |
|---------------|----------------|------|
| Drama | Drama | 剧集（id/title/coverURL/episodeCount） |
| Episode | Episode | 分集（id/index/title/playURL） |
| DramaDetail | DramaDetail | 剧集详情（drama + episodes） |
| FavoriteItem | FavoriteItem (drift) | 收藏 |
| HistoryItem | HistoryItem (drift) | 历史/进度 |
| AppSettings | SettingsRepository (shared_preferences) | 设置 |

### 4. 平台差异处理

| 平台 | 差异点 | 处理 |
|------|--------|------|
| Windows | 窗口管理（老板键/画中画） | window_manager 包 |
| Linux | 系统代理/通知 | 桌面环境差异大，做最小可用 |
| Android | 后台播放/媒体通知 | audio_service 包 |
| Android TV | 遥控器焦点/D-pad 导航 | FocusNode + 自定义焦点遍历 |
| Docker (Web) | 无本地网关（浏览器安全限制） | 网关独立容器，前端直连容器地址 |

### 5. 打包发布

| 平台 | 产物 | 发布方式 |
|------|------|---------|
| Windows | MSIX / ZIP | GitHub Releases（公开仓库） |
| Linux | AppImage / deb / rpm | GitHub Releases |
| Android | APK (arm64-v8a / armeabi-v7a / x86_64) | GitHub Releases |
| Android TV | APK (TV leanback) | GitHub Releases |
| Docker | docker-compose.yml + 镜像 | GitHub Container Registry (ghcr.io) |

## 里程碑

- **M1** Windows 可用版：视频源浏览/搜索/播放（media_kit）+ 收藏/历史 + 设置中心（不含直播/NAS）
- **M2** Windows 完整版 + Linux 可用版：直播/NAS/数据备份对齐 macOS 版
- **M3** Android 手机版：触屏交互适配 + 后台播放
- **M4** Android TV 版：遥控器焦点导航 + TV 布局
- **M5** Docker 本地部署：Flutter Web + 网关容器化 + docker-compose
