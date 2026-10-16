# 剧立方 DramaCube — 全平台影视聚合客户端

> 一个内容世界，三端体验：移动暖阳 / 桌面影院 / TV 焦点引擎。
> 聚合用户自行配置的视频源、直播源、NAS 资源与磁力资源，本地播放、离线下载、零账号依赖。

当前版本：**v2.7.25** ｜ 安装包下载：[DramaCube-releases Releases](https://github.com/g-star1024/DramaCube-releases/releases)

---

## 平台矩阵

| 平台 | 产物 | 界面风格 |
|------|------|----------|
| Windows 10+ | `dramacube-windows-v*.zip` | 桌面 Cinema |
| Linux x64 | `dramacube-linux-v*.tar.gz` | 桌面 Cinema |
| macOS 13+（Intel / Apple Silicon） | `dramacube-macOS-x64/arm64-v*.dmg` | 桌面 Cinema |
| Android 8+ | `dramacube-android-v*.apk` | 移动暖阳 |
| Android TV / 电视模式 | 设置内开启「电视模式」 | TV 独立版（Cinema Dark） |

## 功能总览

**内容聚合**
- 视频源：TVBox / 采集站订阅与本地文件导入（容错解析尾逗号 / BOM / 反爬前缀；`csp_*` App 接口站自动识别并明示跳过），连通性自动测速、失效自动禁用、按延迟排序，默认落到最快源
- 电视直播：M3U / TXT 直播源导入（URL 订阅 + 本地文件），分源浏览或「全部源」合并去重，频道连通性角标，播放沉浸态点击唤出换台栏（5s 自动收起）
- 资源库（NAS）：WebDAV / 本地挂载目录浏览播放，递归视频扫描（限深 5 / 单目录 500），首帧封面后台生成 + 磁盘缓存
- 盘搜：网盘 / 磁力聚合搜索，内置中文友好种子源（动漫花园、TorrentsCSV 等），每源代理 / 直连双通道自动回退，逐源日志可观测

**播放体验**
- media_kit / libmpv 内核：桌面快捷键 OSD、移动端手势、TV 焦点引擎三端分化
- 智能播放：自动连播、跳片头、下集预缓冲（90% 静默预热）、跨源换源续播、秒级进度续播
- 发现页：豆瓣热门 + B 站番剧榜，Cinema Hero 视差轮播

**下载**
- 剧集下载：mp4 流式 + m3u8 多线程分片、断点续传
- 磁力 / BT：进程内 libtorrent 引擎（2.0.x），DHT / LSD / uPnP / NAT-PMP 发现机制全开 + 公共引导节点，元数据解析与下载进度实时可见，任务重启自动恢复

**数据与个性化**
- 收藏 / 播放历史：本地 drift 数据库，「继续观看」跨端续播
- 备份：本地导出 / 导入 + WebDAV 云备份，payload v2 内嵌数据库整文件 + 全部配置，恢复即生效
- 5 套配色主题一键切换（红果粉默认 / 玫瑰金 / 科技蓝 / 森林绿 / 暗夜紫）
- 运行日志：落盘 `~/Library/Logs/DramaCube/`（macOS），设置中心内可查看 / 复制

## 快速开始（源码构建）

```bash
cd apps/flutter
flutter pub get
flutter run -d macos        # 或 windows / linux / android
```

环境要求：Flutter 3.35+（stable），Dart ≥3.5。国内网络建议：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 目录结构（Flutter 版）

```
apps/flutter/lib/
├── app/                    # 主题 / 设计令牌 / 路由 / 设置
├── core/
│   ├── db/                 # drift 数据库（收藏 / 历史）
│   ├── gateway/            # Dart 本地网关（8787，冲突自动降级）
│   ├── models/             # 数据模型（按域拆分：catalog/live/nas + 兼容门面）
│   ├── torrent/            # libtorrent FFI 绑定
│   └── widgets/            # 通用组件（CinemaHero / MediaRow / Shimmer…）
└── features/
    ├── discover/           # 发现页（豆瓣 / B 站榜单）
    ├── catalog/            # 视频源（TVBox / 采集站）
    ├── live/               # 电视直播
    ├── nas/                # 资源库（WebDAV / 挂载）
    ├── panso/              # 盘搜（网盘 / 磁力聚合搜索）
    ├── torrent/            # 种子搜索源管理
    ├── downloads/          # 下载管理（剧集 + 磁力）
    ├── detail/             # 详情页
    ├── player/             # 播放器（三端 OSD 分化）
    ├── library/            # 收藏 / 历史
    ├── settings/           # 设置中心
    └── tv/                 # TV 独立版
```

模块边界规范见 [`apps/flutter/MODULE_BOUNDARY.md`](apps/flutter/MODULE_BOUNDARY.md)：视频源 / 资源库 / 直播 / 盘搜四模块代码自治、模型按域隔离，禁止跨模块改动相互破坏。

## 发版机制

源码在私有仓 `hongguo-desktop`；本仓（DramaCube-releases）的 GitHub Actions 用 PAT checkout 源码后五平台并行构建，产物发布到本仓 Releases（公开仓 Actions 免费）。

```bash
# 手动发版
gh workflow run build.yml -R g-star1024/DramaCube-releases -f ref=main -f version=2.7.25
# 或向本仓 main 分支 push 触发（版本号取 workflow 默认值）
```

## 版本摘要

| 版本 | 要点 |
|------|------|
| **v2.7.25** | 修复日志落盘后的 StreamSink 首启崩溃（串行 flush） |
| **v2.7.24** | 备份 payload v2（全量覆盖 + 恢复即生效）；种子搜索双通道回退 + 引擎启动预热；中文种子源内置；TVBox 容错导入；日志落盘修复 |
| **v2.7.23** | 直播播放沉浸态（隐藏主导航 + 换台工具栏自动收起） |
| **v2.7.8** | 视频源/直播源本地导入 + WebDAV 云备份 + TV 全功能设置中心 |
| **v2.7.0** | 源连通性体系 + 三页源切换 + 5 套配色主题 |

完整历史见 Releases 各版本说明。

## 合规说明

本项目为个人学习/研究用途的第三方客户端，不托管任何影视内容，所有数据来自用户自行配置的公开接口；请遵守所在地法律法规与内容服务方条款。详见软件内「设置 → 关于 → 用户协议 / 免责声明」。
