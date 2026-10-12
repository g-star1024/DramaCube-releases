# 剧立方 DramaCube — 全平台发布仓库

多端短剧聚合播放客户端（Flutter）的 Release 产物发布仓库。

- Windows / Linux / macOS（Intel + Apple Silicon）/ Android / Android TV / Docker
- 源码在私有仓库 hongguo-desktop（不公开）

## 下载（最新 v2.7.0）

| 平台 | 文件 | 说明 |
|------|------|------|
| Windows 10/11 | `dramacube-windows-v2.7.0.zip` | 解压后运行 `dramacube.exe` |
| Linux x64 | `dramacube-linux-v2.7.0.tar.gz` | 解压后 `./dramacube` |
| macOS Apple Silicon | `dramacube-macOS-arm64-v2.7.0.dmg` | M1/M2/M3/M4 |
| macOS Intel | `dramacube-macOS-x64-v2.7.0.dmg` | x86_64 |
| Android 8+ | `dramacube-android-v2.7.0.apk` | 手机 / 平板 / Android TV |

历史版本见 [Releases 列表](https://github.com/g-star1024/DramaCube-releases/releases)。

## 功能

- **发现**：豆瓣热门（电影/剧集/综艺/动漫）+ B 站番剧榜；桌面 Cinema Hero 视差轮播、移动双列瀑布流
- **聚合搜索**：TVBox 多源并发搜索，按源分组，「搜到一个显一个」；**点击结果直接播放**，长按查看详情
- **源连通性**：自动测速，默认延迟最低的源；失效源自动禁用并按延迟排序；手动切换后锁定选择
- **三页源切换**：视频源 / 直播 / 资源库页右上角一键切换，实时延迟徽标；直播可分源浏览或全部合并
- **一键测速**：设置中心并发探测全部源，失效自动禁用，结果汇总提示
- **配色主题**：5 套色板（红果粉 / 玫瑰金 / 科技蓝 / 森林绿 / 暗夜紫）设置内一键切换
- **详情**：沉浸式封面头图 + 豆瓣简介 + 跨源换源 + 选集
- **播放器**（libmpv 内核）：
  - 桌面：毛玻璃 OSD、全套快捷键（`Space` `←→` `↑↓` `F` `Esc` `0-9` `[ ]`）、暂停氛围模式
  - 移动：双击快进退、边缘滑调亮度/音量
  - TV：焦点引擎（缩放 + 金辉光 + 邻居压暗）、大按钮 OSD、双击 OK 2 倍速
- **智能播放**：自动连播、跳片头、下集预缓冲、换源续播
- **下载管理**：mp4 流式 + m3u8 多线程分片 + 断点续传
- **直播**：M3U/TXT 直播源（连通性探测 + 失效自动禁用）；**资源库**：WebDAV / 本地目录
- **收藏 / 历史**：本地数据库，「继续观看」跨设备续播

## 三端风格

| | 移动 | 桌面 | TV |
|---|------|------|-----|
| 主题 | 暖阳奶油 | 暖阳奶油 + 影院深色 | Cinema Dark 影院深色 |
| 布局 | 瀑布流 + 底部导航 | 16:6 Hero + 陈列栏 | 聚光灯 + 常驻侧栏 |
| 交互 | 手势 | 快捷键 + 悬停 | 遥控焦点引擎 |

「电视模式」：App 内 设置 → 通用 → 开启「电视模式」，或直接安装到 Android TV 使用。

## 安装说明

- **macOS**：首次打开如提示「已损坏」，执行 `xattr -cr /Applications/DramaCube.app`（ad-hoc 签名，未做 Developer ID 公证）。
- **Windows**：SmartScreen 提示时选择「更多信息 → 仍要运行」。
- **Android**：允许「安装未知来源应用」。
- **Docker**：`docker load < dramacube-docker-*.tar.gz` 后运行，Web 走 8080 端口（历史版本提供）。

## 版本历史

- **v2.7.0** — 源连通性体系（自动测速 / 失效禁用 / 延迟排序 / 默认最快源）+ 三页右上角源切换 + 5 套配色主题一键切换 + 搜索结果点击即播
- **v2.6.0** — UI 三端升级：Cinema Hero / 毛玻璃 OSD / 快捷键 / 暂停氛围模式 / TV 独立版 / 继续观看
- **v2.4.1** — 修复 macOS 黑屏（网关端口冲突）
- **v2.4.0** — 新增 macOS Intel + Apple Silicon 双架构
- **v2.3.0** — Docker 镜像

## 合规说明

本项目为个人学习/研究用途的第三方客户端，不托管任何影视内容，所有数据来自公开接口；请遵守所在地法律法规与内容服务方条款。
