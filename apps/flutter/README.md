# 剧立方 DramaCube (Flutter)

全平台短剧聚合客户端 —— Windows / Linux / macOS（Intel + Apple Silicon）/ Android / Web / Docker / TV。

当前版本 **v2.7.0**（新增：源连通性体系 + 三页源切换 + 5 套配色主题 + 搜索即播；UI 三端：移动暖阳奶油 / 桌面 Cinema / TV 独立版）。

## 功能

- 发现：豆瓣热门 + B 站番剧榜（桌面 Cinema Hero 16:6 视差轮播 / 移动双列瀑布流）
- 聚合搜索：TVBox 多源并发，按源分组流式呈现；**点击直接播放**（自动拉详情进播放器），长按进详情
- 源连通性：首启/导入订阅自动测速，默认最快源；失效源自动禁用（全失效保留一个），延迟排序；手动切换后 pinned 锁定
- 三页源切换：视频源 / 直播 / 资源库页右上角 ⇄ 弹层切换，HealthBadge 实时延迟（灰=未测 / 绿=可用 ms / 红=失效）；直播支持分源或全部合并去重；资源库仅标记不禁用
- 设置中心一键测速：并发探测 + 失效自动禁用 + Snackbar 汇总
- 配色主题：5 套色板（红果粉默认 / 玫瑰金 / 科技蓝 / 森林绿 / 暗夜紫），设置 → 浏览一键切换，持久化，TV 焦点联动
- 详情：沉浸式封面铺底头图 + 跨源可播版本 + 选集网格
- 播放器（media_kit / libmpv）：
  - 桌面：毛玻璃 OSD、快捷键（Space/←→/↑↓/F/Esc/0-9/[ ]）、暂停氛围模式
  - 移动：双击快进退、边缘滑亮度/音量
  - TV：焦点 scrubber、双击 OK 2x
- 自动连播 / 跳片头 / 下集预缓冲 / 换源续播
- 下载：mp4 流式 + m3u8 多线程分片 + 断点续传
- 直播（M3U/TXT）、WebDAV/挂载资源库、收藏与历史（drift）、继续观看
- 本地网关：8787（冲突自动降级 8787-8791），`GET /api/health`

## 开发

```bash
flutter pub get
flutter run -d <macos|windows|linux|android|chrome>
flutter analyze          # 交付前必须 0 issues
flutter build web --release
```

国内镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。

## 结构

```
lib/
├── app/          主题 / design_system 令牌 / motion 动效 / router / settings
├── core/         db(drift) / gateway / models / widgets(通用组件)
└── features/     discover catalog detail player downloads live nas
                  library search settings tv(TV 独立版)
```

平台工程目录：`android/ macos/ windows/ linux/ web/`，容器化：`Dockerfile` + `docker-compose.yml`（Web + nginx + Dart 网关，8080 端口）。

## TV 模式

设置 → 通用 → 「电视模式」：切换 Cinema Dark 主题 + 焦点引擎（缩放 1.12 + 金辉光 + 邻居压暗）+ 常驻侧栏 + 安全区（上下 60dp / 左右 80dp）。

## 发布

CI 在公开仓 [DramaCube-releases](https://github.com/g-star1024/DramaCube-releases)  Actions 运行（私有仓 Actions 受额度限制）：改 `pubspec.yaml` 版本号 → 推送私有仓 → 在公开仓 dispatch 三条 workflow（windows / linux+android / macos 双架构）。

设计文档：`docs/flutter-ui-upgrade-v2.5.md`（三端分风格方案）。
