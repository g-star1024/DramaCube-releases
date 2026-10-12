# 剧立方 DramaCube — 全平台短剧客户端

> 多端短剧聚合播放客户端：**一个内容世界，三端体验**（移动暖阳 / 桌面影院 / TV 焦点引擎）。
> 基于 TVBox / 豆瓣公开接口聚合全网短剧与影视资源，本地播放、离线缓存、零账号依赖。

---

## 一、仓库结构（Monorepo）

| 目录 | 客户端 | 状态 |
|------|--------|------|
| [`apps/flutter`](apps/flutter) | **剧立方 DramaCube Flutter 全平台版**（v2.7.1） | 主推，活跃开发 |
| `Sources/` + `HongguoDesktopMac/` | 红果短剧 macOS 原生版（Swift 6 + SwiftUI + Hummingbird 网关） | 稳定维护 |

发布策略：源码在本私有仓，安装包在公开仓 [`g-star1024/DramaCube-releases`](https://github.com/g-star1024/DramaCube-releases) 分发。

## 二、平台矩阵（Flutter 版 v2.7.1）

| 平台 | 产物 | 风格 |
|------|------|------|
| Windows 10+ | `dramacube-windows-*.zip` | 桌面 Cinema |
| Linux x64 | `dramacube-linux-*.tar.gz` | 桌面 Cinema |
| macOS 13+（Intel / Apple Silicon 双架构） | `dramacube-macOS-x64/arm64-*.dmg` | 桌面 Cinema |
| Android 8+ | `dramacube-android-*.apk` | 移动暖阳 |
| Android TV / 电视模式 | 设置开启「电视模式」 | TV 独立版（Cinema Dark） |
| Web / Docker | `flutter build web` + `Dockerfile` | 桌面 Cinema |

## 三、功能总览

- **发现**：豆瓣热门（电影/剧集/综艺/动漫）+ B 站番剧榜，桌面 Cinema Hero 16:6 视差轮播、移动双列瀑布流
- **聚合搜索**：TVBox 多源并发搜索，「搜到一个显一个」按源分组；**点击结果直接播放**（自动拉取详情进入播放器），长按才进详情页
- **源连通性体系**：首次启动/导入订阅后自动测速，默认展示延迟最低的源；失效源自动禁用（全失效时保留一个防无源），按延迟自动排序；用户手动切换后锁定选择（`pinned`），不再自动跟随
- **三页源切换**：视频源页 / 直播页 / 资源库页右上角 `⇄` 一键切换（底部弹层 + 实时延迟徽标：未测灰 / 可用绿 `123 ms` / 失效红）；直播支持分源浏览或「全部源」合并去重；资源库探测仅打徽标不自动禁用（NAS 可能只是临时慢）
- **设置中心一键测速**：并发探测全部视频源，失效自动禁用并按延迟排序，Snackbar 汇总「X 个源可用，Y 个失效源已自动禁用」
- **配色主题**：5 套色板一键切换（红果粉默认 / 玫瑰金 / 科技蓝 / 森林绿 / 暗夜紫），设置 → 浏览 → 配色主题，选择持久化，TV 焦点色联动
- **详情**：封面铺底沉浸式头图 + 豆瓣简介 + 跨源可播版本切换 + 选集胶囊网格
- **播放器**（media_kit / libmpv 内核）：
  - 桌面：毛玻璃 OSD、快捷键（`Space` `←→` `↑↓` `F` `Esc` `0-9` `[ ]`）、暂停氛围模式
  - 移动：双击快进退、边缘滑调亮度/音量、横屏沉浸
  - TV：焦点 scrubber、大按钮 OSD、双击 OK 2 倍速
- **智能播放**：自动连播、跳片头、下集预缓冲（90% 静默预热）、跨源换源续播
- **下载管理**：mp4 流式下载 + m3u8 多线程分片下载与断点续传
- **直播**：M3U/TXT 直播源聚合（连通性探测 + 失效自动禁用）
- **资源库**：WebDAV / 本地挂载目录浏览播放（PROPFIND 延迟探测）
- **收藏 / 播放历史**：本地 drift 数据库，「继续观看」跨端续播
- **本地网关**：Dart HTTP 网关（8787 端口，冲突时 8787-8791 自动降级），`/api/health` 可查版本

## 四、三端设计语言（v2.5 起）

统一品牌基底 **红果粉 #FF2D55 + 粉金渐变 #FF2D55 → #FF9A62 → #FFD666**，表现层分端：

| | 移动 | 桌面 | TV |
|---|------|------|-----|
| 主题 | 暖阳奶油（#FDFBF7） | 暖阳奶油 + 影院深色 | Cinema Dark（#0E0D0B） |
| 布局 | 双列瀑布流 + 底部导航 | 16:6 Hero + 陈列栏行（末项露出 30%） | 聚光灯 + 常驻窄轨侧栏（56→200dp） |
| 交互 | 手势（双击/边缘滑） | 快捷键 + 悬停预览 | D-pad 焦点引擎（缩放 1.12 + 金辉光 + 邻居压暗） |
| 安全区 | 系统默认 | 系统默认 | 上下 60dp / 左右 80dp，字阶 ≥1.5x |

**配色主题（v2.7.0 起）**：色板参数化（强调色 / 背景 / 胶囊 / 分隔 / Hero 渐变 / TV 焦点共 17 色），内置 5 套——红果粉（默认）、玫瑰金、科技蓝、森林绿、暗夜紫，设置 → 浏览 → 「配色主题」一键切换，选择持久化，TV 焦点色跟随联动。

设计规范与演进路线见 [`docs/flutter-ui-upgrade-v2.5.md`](docs/flutter-ui-upgrade-v2.5.md)。

## 五、快速开始（Flutter 版）

```bash
cd apps/flutter
flutter pub get
flutter run -d macos        # 或 windows / linux / android / chrome
flutter build web --release # Web 构建
```

环境要求：Flutter 3.35+，Dart SDK ≥3.5。国内网络建议配置：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 六、目录结构（Flutter 版）

```
apps/flutter/lib/
├── app/                    # 主题 / 设计令牌 / 路由 / 设置
│   ├── design_system.dart  #   Brand 色板 + 间距 + 圆角 + v3 渐变/焦点令牌
│   ├── motion.dart         #   动效令牌（150/250/400ms + 曲线）
│   └── router.dart         #   go_router（宽屏 Rail / 窄屏底栏）
├── core/
│   ├── db/                 # drift 数据库（收藏 / 历史）
│   ├── gateway/            # Dart 本地网关（8787）
│   ├── models/             # 数据模型
│   └── widgets/            # 通用组件（CinemaHero / MediaRow / Shimmer…）
└── features/
    ├── discover/           # 发现页 + 豆瓣/B站引擎
    ├── catalog/            # TVBox 视频源 + 聚合搜索
    ├── detail/             # 详情页
    ├── player/             # 播放器（三端 OSD 分化）
    ├── downloads/          # 下载管理（mp4 / m3u8 多线程）
    ├── live/               # 直播
    ├── nas/                # WebDAV / 挂载资源库
    ├── library/            # 收藏 / 历史
    ├── search/             # 聚合搜索页
    ├── settings/           # 设置中心
    └── tv/                 # TV 独立版（主题/焦点/侧栏/键盘/OSD/五页）
```

## 七、版本历史

| 版本 | 内容 |
|------|------|
| **v2.7.1** | hotfix：修复视频源空键毒丸（`testAll`/禁用当前源后持久化空 `currentSource` → 全站无可播放内容，全路径自愈）；修复大屏目录页只加载首页+底部无限转圈（内容不满屏时滚动监听不触发 → 自动续页）；修复搜索结果滚动到底重复追加；**全新品牌图标**（极简播放键，全平台替换）；宽屏导航栏头部加 App 图标；**macOS 菜单栏常驻小图标**（模板渲染自适应深色菜单栏，点开 打开/显隐/退出） |
| **v2.7.0** | 源连通性体系（自动测速/失效禁用/延迟排序/默认最快源）+ 三页右上角源切换（视频源/直播/资源库）+ 5 套配色主题一键切换 + 搜索结果点击即播 |
| **v2.6.0** | UI 三端升级：令牌 v3、Cinema Hero、毛玻璃 OSD、快捷键、暂停氛围模式、TV 独立版（焦点引擎 + Cinema Dark）、继续观看 |
| v2.4.1 | 修复 macOS 黑屏（网关端口占用未捕获异常 → 8787-8791 降级） |
| v2.4.0 | 新增 macOS 双架构（Intel / Apple Silicon）构建 |
| v2.3.0 | Docker 镜像（Web + nginx + Dart 网关） |

安装包下载：[DramaCube-releases](https://github.com/g-star1024/DramaCube-releases/releases)

## 八、合规说明

本项目为个人学习/研究用途的第三方客户端，不托管任何影视内容，所有数据来自公开接口；
请遵守所在地法律法规与内容服务方条款。
