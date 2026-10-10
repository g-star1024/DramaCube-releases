# 剧立方 对标 Cinetry — 升级重构方案

> 版本：v2.0 规划稿 ｜ 日期：2026-10-10
> 竞品：Cinetry 0.8.4+48（com.gstory.cinetry，Flutter macOS，最低 macOS 12.0）
> 目标：对标 Cinetry 的多媒体服务器聚合客户端模式，**超越它**——做成「数据源聚合 + 强播放 + 中文短视频/采集源生态」三合一的本地客户端。

---

## 一、竞品分析：Cinetry 是什么、强在哪

### 1.1 产品定位（一句话）

> Cinetry 是**纯本地、不提供任何数据**的跨平台客户端，整合用户自己添加的媒体服务器（Jellyfin / Emby / CMS / WebDAV / Subsonic / Navidrome / GD音乐台 / audiobookshelf / 道理鱼 / IPTV / AList·OpenList），通过**数据导入 + 聚合搜索 + 一键切换**，让用户统一管理多台媒体服务器。

关键词：**不扫库**（只通过接口拉当前页所需数据）、**聚合**、**跨平台一致**。

### 1.2 技术栈拆解（从 DMG 二进制取证）

| 维度 | 事实 | 取证来源 |
|------|------|---------|
| 应用框架 | **Flutter macOS**（非原生 Swift） | `FlutterMacOS.framework` / `App.framework`（Dart AOT） |
| 播放内核 | **media_kit（libmpv/mpv）** + mdk + fvp + AVFoundation 多引擎 | `Mpv.framework` / `media_kit_video.framework` / `mdk.framework` / `video_player_avfoundation` |
| 视频解码 | FFmpeg 全家桶（Avcodec/Avformat/Avfilter/Avutil/Swscale/Swresample）+ Dav1d（AV1） | 对应 .framework |
| 字幕 | **libass**（ASS/SSA 特效字幕）+ Freetype/Fribidi/Harfbuzz/Uchardet（编码嗅探） | `Ass.framework` 等 |
| 内嵌 Web | flutter_inappwebview（内嵌网页登录/播放） | 对应 .framework |
| 本地存储 | sqflite + shared_preferences | 对应 .bundle |
| 系统能力 | system_tray（托盘）/ mobile_scanner（扫码连服务器）/ file_picker / share_plus / wakelock | 对应 .bundle |
| 包体 | 62.8 MB（universal x86_64+arm64） | DMG 实测 |

### 1.3 功能指纹（从 Dart AOT 字符串 + 官方文档取证）

- **数据源**：Emby/Jellyfin（`/emby/Items`、`/emby/Users/AuthenticateByName`、`/emby/Sessions/Playing` 全套）、AppleCMS（`api_key=`）、WebDAV、AList/OpenList（`/api/fs/list`、`/api/fs/get`）、Subsonic/Navidrome（`/rest/scrobble`、`/api/song`、`/api/album`）、audiobookshelf（`/api/libraries`、`/api/me`、`/api/playlog`）、IPTV（m3u）。
- **播放**：倍速（playbackSpeed）、音轨切换（audioTracks）、Emby/Jellyfin **服务端转码**（EnableTranscoding / EnableTranscodingQuality / HLS master playlist）、HDR / Dolby Vision / Dolby Atmos、`.nfo` 元数据读取。
- **弹幕**：`/danMu/send`、`/danMuApi`、`DanmakuItem`、`danMuArea`（底部弹幕/区域弹幕），支持弹幕收发。
- **聚合搜索**：跨服务器全局搜索，按标题/演员/导演/年份，模糊匹配 + 按类型过滤 + 相关性排序。
- **离线缓存**：提前下载，离线观看。
- **权限/家长控制**：儿童内容分级访问。
- **数据导出**：目前仅支持 AppleCMS 与 IPTV 数据导出（不自动订阅，导入即覆盖）。
- **主题**：深/浅色模式、字体大小调节，跨平台 UI 一致。

### 1.4 Cinetry 的护城河（值得学的）

1. **统一抽象层**：把 10+ 种异构服务器收敛成一个「媒体服务器」模型，上层 UI/搜索/播放只面对一个协议。
2. **服务端转码借力**：不自己转码，直接调 Emby/Jellyfin 的转码能力出 HLS，弱机也能播高码率。
3. **media_kit 播放内核**：mpv 解码能力远超 AVPlayer（格式全、ASS 字幕、音轨/倍速/转码成熟）。
4. **跨平台同一套 UI**：Flutter 一套代码覆盖 6 端，降低维护成本。
5. **弹幕社交层**：弹幕让播放不再是孤岛。

---

## 二、我们的现状：差距与底牌

### 2.1 现有架构（10628 行 Swift）

```
HongguoCore         基础（DirectURLSession 强制直连等）
HongguoGatewayCore  本地网关（Hummingbird HTTP）
  ├─ GatewayServer   路由编排 /api/*
  ├─ TVBoxEngine     AppleCMS 采集站（maccms）
  ├─ CoverEngine     豆瓣封面/热门 + image-proxy 防盗链
  ├─ LiveEngine      IPTV m3u 直播
  └─ NASEngine       WebDAV/mount（多服务器雏形）
HongguoDesktopMac   SwiftUI UI 层
  └─ Features/{Catalog,Downloads,Library,Live,Player,Settings}
HongguoGateway      网关可执行入口
```

### 2.2 差距清单（对标 Cinetry）

| 能力 | Cinetry | 剧立方现状 | 差距 |
|------|---------|-----------|------|
| **播放内核** | media_kit/libmpv | **AVPlayer** | ⚠️ 最大短板：格式支持、ASS 字幕、音轨、转码全面落后 |
| 媒体服务器 | 10+ 种统一抽象 | WebDAV/mount（NASEngine 雏形）+ CMS + IPTV 各自为政 | ⚠️ 无统一抽象层，无 Jellyfin/Emby/Subsonic/audiobookshelf/AList |
| 聚合搜索 | 跨服务器全局搜索 | 单源搜索 | ⚠️ 缺失 |
| 服务端转码 | Emby/Jellyfin 转码 HLS | 无 | ⚠️ 缺失 |
| 字幕 | libass ASS 特效 | AVPlayer 基础字幕 | ⚠️ 落后 |
| 弹幕 | 收发弹幕 | 无 | ❌ 缺失 |
| 音乐服务器 | Subsonic/Navidrome/GD | 无 | ❌ 缺失 |
| 听书 | audiobookshelf | 无 | ❌ 缺失 |
| 图片代理 | processImageUrl | ✅ 已有（image-proxy 防盗链） | ✅ 持平 |
| 直连优化 | 未针对中国大陆代理优化 | ✅ DirectURLSession 强制直连 | ✅ **我们领先** |
| 短视频/采集源 | 无 | ✅ 红果短剧 + TVBox 采集站生态 | ✅ **我们领先（差异化）** |
| 直播 IPTV | m3u | ✅ 已有 LiveEngine + 209 频道实测 | ✅ 持平偏强 |
| 跨平台 | 6 端（Flutter） | 仅 macOS（Swift 原生） | ⚠️ 但我们体验更原生 |

### 2.3 我们的底牌（不可丢的差异化）

1. **DirectURLSession 强制直连**：解决中国大陆系统代理境外出口被采集站 CDN 拦截——Cinetry 没有，这是我们的硬实力。
2. **红果短剧 + TVBox 采集站生态**：海量免费短剧/影视，Cinetry 完全不具备。
3. **本地网关架构**：统一的反爬/防盗链/代理/缓存层，是承接多服务器的天然底座。
4. **豆瓣封面/热门**：中文影视元数据 + 海报，Cinetry 靠 TMDB，中文体验我们更好。

**结论：不推倒重来，而是「吸收 Cinetry 的统一抽象 + 强播放内核，嫁接在我们的网关 + 短剧生态上」。**

---

## 三、重构总纲：从「多源浏览器」到「统一媒体中枢」

### 3.1 核心理念转变

| 旧范式 | 新范式 |
|--------|--------|
| 每个数据源一套 UI/逻辑 | 一个 `MediaServer` 协议，全部收敛 |
| AVPlayer 包打天下 | libmpv 内核（可回退 AVPlayer） |
| 单源搜索 | 跨服务器聚合搜索 |
| 视频为中心 | 视频 + 音乐 + 听书 + 直播 + 短剧 全媒体 |

### 3.2 目标架构

```
┌─────────────────────────────────────────────────────┐
│                   SwiftUI UI 层                      │
│  首页聚合 / 发现 / 媒体库 / 搜索 / 播放 / 设置        │
└──────────────────────┬──────────────────────────────┘
                       │ 只依赖统一模型，不认具体源
┌──────────────────────▼──────────────────────────────┐
│            MediaServerRegistry（服务器注册中心）      │
│   一键切换 · 连接状态 · 多服务器管理 · 聚合调度        │
└──────────────────────┬──────────────────────────────┘
                       │ 统一协议 MediaServerProtocol
   ┌──────────┬────────┼────────┬─────────┬──────────┐
   ▼          ▼        ▼        ▼         ▼          ▼
 Jellyfin   Emby    WebDAV   AList/    Subsonic/  TVBox·CMS
 适配器    适配器   适配器   OpenList  Navidrome  适配器(已有)
   │          │        │      适配器    适配器      │
   │          │        │        │ audiobookshelf    │
   │          │        │        │   适配器  IPTV适配器│
   └──────────┴────────┴────────┴─────────┴──────────┘
                       │ 全部走本地网关（直连+反爬+缓存）
┌──────────────────────▼──────────────────────────────┐
│          本地网关 GatewayServer（Hummingbird）         │
│  DirectURLSession 直连 · image-proxy · 转码HLS · 缓存  │
└──────────────────────┬──────────────────────────────┘
                       │
              ┌────────▼─────────┐
              │  libmpv 播放内核   │ ← 统一播放，回退 AVPlayer
              └──────────────────┘
```

---

## 四、分模块重构方案（8 大工作包）

### WP1 · 统一媒体服务器抽象层（**地基，最高优先级**）

定义协议，所有数据源实现它。这是 Cinetry 的精髓。

```swift
/// 统一媒体服务器协议（新架构地基）
public protocol MediaServerProtocol: Sendable {
    var id: String { get }
    var kind: MediaServerKind { get }      // jellyfin/emby/webdav/alist/subsonic/abs/tvbox/iptv
    var displayName: String { get }

    /// 连接测试 + 能力探测（对标 Cinetry 实时连接状态检查）
    func probe() async -> ServerCapability

    /// 拉取媒体库列表（电影库/剧集库/音乐库/直播...）
    func libraries() async throws -> [MediaLibrary]

    /// 拉某个库的内容（分页，对标「不扫库只拉当前页」）
    func items(library: String, page: Int, limit: Int) async throws -> MediaPage

    /// 详情（含剧集列表、音轨、字幕、nfo 元数据）
    func detail(item: String) async throws -> MediaDetail

    /// 播放地址解析（直链 / 转码HLS / 需网关代理）
    func playback(item: String, quality: Quality?) async throws -> PlaybackSource

    /// 搜索（本服务器内）
    func search(query: String, filter: SearchFilter) async throws -> [MediaItem]

    /// 播放进度上报（对标 /emby/Sessions/Playing、/rest/scrobble）
    func reportProgress(item: String, position: TimeInterval, state: PlayState) async
}
```

统一模型：`MediaItem`（id/title/poster/year/rate/type/来源 serverId）、`MediaLibrary`、`MediaDetail`、`PlaybackSource`（direct / transcodeHLS / proxied）。

**产出**：`Sources/HongguoGatewayCore/MediaServer/` 目录，协议 + 模型 + Registry。

### WP2 · 适配器实现（按优先级分批）

| 批次 | 适配器 | 复用 | 工作量 |
|------|--------|------|--------|
| P0 | TVBox·CMS（重构现有 TVBoxEngine 包成适配器） | ✅ 已有 | 小 |
| P0 | WebDAV/mount（重构 NASEngine 包成适配器） | ✅ 已有 | 小 |
| P0 | IPTV（重构 LiveEngine 包成适配器） | ✅ 已有 | 小 |
| P1 | **Emby**（`/emby/Items`、`AuthenticateByName`、`Sessions/Playing`、转码） | 新增 | 中 |
| P1 | **Jellyfin**（与 Emby 高度同构，共用基础） | 新增 | 中 |
| P2 | **AList/OpenList**（`/api/fs/list` 网盘聚合） | 新增 | 中 |
| P2 | **Subsonic/Navidrome**（音乐，`/rest/*`） | 新增 | 中 |
| P3 | audiobookshelf（听书） | 新增 | 中 |
| P3 | 红果短剧（包装成内置适配器） | ✅ 已有 | 小 |

### WP3 · 播放内核升级：AVPlayer → libmpv（**体验飞跃**）

- 引入 `media_kit` 的 macOS 产物 `Mpv.framework`（或独立编译 libmpv），Swift 侧用薄封装。
- 能力解锁：全格式解码、**ASS/SSA 特效字幕**、多音轨切换、倍速、硬解（VideoToolbox）、HDR/Dolby Vision。
- 保留 AVPlayer 作为回退（`PlaybackEngine` 枚举：`.mpv` / `.avplayer` 可切换）。
- 播放设置全局化复用现有 `AppSettings`。

**风险**：libmpv 集成是最大技术风险点，需先出 PoC 验证字幕/音轨/硬解再全面替换。

### WP4 · 服务端转码借力（对标 Cinetry 转码 HLS）

- Emby/Jellyfin 适配器实现 `PlaybackInfo` 转码请求，拿 HLS master playlist。
- 网关层增加「转码 HLS 重写」（把转码分片走本网关，复用现有 m3u8 重写逻辑）。
- 弱机/高码率场景自动降级转码。

### WP5 · 跨服务器聚合搜索 + 聚合首页

- `MediaServerRegistry.aggregateSearch()`：并发查所有已启用服务器，按相关性归并排序，标注来源。
- 首页聚合「继续观看」（各服务器上报的进度合并）、「最新入库」（各库按时间归并）。
- 复用现有豆瓣热门做「发现」兜底。

### WP6 · 播放进度与继续观看（对标 Sessions/Playing + scrobble）

- 本地持久化播放进度（Application Support），跨源「继续观看」聚合。
- 对已登录的 Emby/Jellyfin/Subsonic 上报进度（服务端 scrobble）。

### WP7 · 弹幕层（**超越点**，Cinetry 有但我们可做得更贴中文生态）

- libmpv 渲染层上叠弹幕视图（SwiftUI overlay）。
- 弹幕源：弹弹play API + 本地弹幕文件（xml/ass）。
- 短剧/影视场景弹幕，Cinetry 弹幕较通用，我们可针对中文内容优化匹配。

### WP8 · UI 重构：统一媒体中枢首页

- 左侧服务器切换栏（对标 Cinetry 一键切换 + 实时连接状态指示）。
- 首页 = 聚合继续观看 + 各库最新 + 发现（豆瓣热门）。
- 深/浅主题 + 字体调节（对标 Cinetry 个性化）。
- **保留**现有 SwiftUI 原生体验优势，不迁 Flutter（我们的原生体验是差异化，迁 Flutter 是退步）。

---

## 五、实施路线图（4 个里程碑）

```
M1「统一抽象」  2 周
  WP1 协议+Registry + WP2 P0 适配器(TVBox/WebDAV/IPTV 包成协议)
  → 三个现有源跑在新架构上，UI 不破

M2「强播放」    2-3 周
  WP3 libmpv PoC→集成（字幕/音轨/倍速/硬解）+ WP4 Emby/Jellyfin 转码
  → 播放能力追平 Cinetry

M3「多服务器」  2 周
  WP2 P1(Emby/Jellyfin)+P2(AList/Subsonic) + WP5 聚合搜索/首页 + WP6 进度
  → 多服务器中枢成型，对齐 Cinetry 核心

M4「超越」     持续
  WP7 弹幕 + WP8 UI 精修 + 听书/音乐补齐
  → 在中文生态（短剧+采集源+豆瓣+弹幕）上超越 Cinetry
```

---

## 六、超越点清单（做完即领先）

| # | 超越点 | 依据 |
|---|--------|------|
| 1 | **中国大陆网络直连优化**（DirectURLSession） | Cinetry 无，系统代理境外出口会被采集站拦 |
| 2 | **短剧 + 免费采集源生态** | Cinetry 只做自建服务器，不碰免费源 |
| 3 | **豆瓣中文元数据 + 海报** | Cinetry 靠 TMDB，中文检索弱 |
| 4 | **原生 macOS 体验**（SwiftUI，菜单栏/托盘/快捷键） | Cinetry 是 Flutter，原生度低 |
| 5 | **弹幕中文内容匹配** | 弹弹play + 中文影视库，比 Cinetry 通用弹幕更准 |
| 6 | **本地网关反爬/防盗链层** | 统一的封面/播放代理，Cinetry 分散处理 |

---

## 七、风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| libmpv 集成复杂、包体膨胀 | 高 | 先出 PoC 验证字幕/硬解；按需裁剪 FFmpeg；包体可接受 60MB 内（对标 Cinetry 62.8MB） |
| 10+ 适配器工作量大 | 中 | 分批交付（P0→P3），每批可用；Emby/Jellyfin 同构共用 |
| 重构破坏现有稳定功能 | 高 | 适配器先包现有引擎（TVBox/WebDAV/IPTV），UI 逐步切，全程可回退 |
| 服务端转码兼容性 | 中 | 复用现有 m3u8 重写；保留直链回退 |
| 进度不同步/状态错乱 | 低 | 本地持久化为准，服务端上报尽力而为 |

---

## 八、跨平台技术路线（已拍板：不迁 Flutter）

### 8.1 拓展性 vs 跨平台 的权衡结论

| 维度 | 原生 Swift | Flutter | 结论 |
|------|-----------|---------|------|
| 拓展性（功能做多深） | **强**：系统新 API 当天可用、菜单栏/托盘/老板键/NowPlaying 原生集成、libmpv C API 直接调、无引擎层包体小 | 弱：靠插件桥接，滞后且能力打折，自带渲染引擎包体大(Cinetry 62.8MB) | 重系统能力的播放器，原生赢 |
| 跨平台方便度 | 每端一套，复用率低 | **一套代码 6 端**，UI 天然一致 | 上 Android/Windows/TV 时 Flutter 省心 |

### 8.2 决策：macOS 端坚持原生，跨平台走「共享内核 + 各端原生 UI」

- **不迁 Flutter**——我们的差异化（原生系统集成、DirectURLSession 网络栈定制、轻量包体）正是 Cinetry(Flutter) 做不到的，迁 Flutter 等于自废武功追平对手。
- **苹果生态内跨平台（macOS + iOS/iPadOS）**：SwiftUI 高度复用，网关/引擎/适配器是纯 Swift 无 UI，可直接搬 iOS。原生已够，无需 Flutter。
- **未来上 Android/Windows/TV**：复用的是**业务逻辑而非全部 UI**。把 `HongguoGatewayCore`（网关/引擎/采集/适配器）保持与 UI 无关的独立层；真跨端时可用 Kotlin Multiplatform / Rust 重写这层共享内核，各端再套原生薄 UI，而非整套换 Flutter。

### 8.3 对协议设计的约束（全平台方案）

`MediaServerProtocol` 必须**与 UI 无关、与平台无关**：纯 Swift、只依赖 Foundation、模型全部 Codable+Sendable，不 import SwiftUI/AppKit。这样同一套协议和适配器未来可原样编译到 iOS，或平移到 KMP/Rust。

---

## 九、立即可启动的第一步（建议）

1. **WP1 协议设计评审**——先把 `MediaServerProtocol` 契约定下来（这是所有后续的地基，需你拍板契约形态）。
2. **WP3 libmpv PoC**——并行起一个最小播放 demo，验证 ASS 字幕 + 硬解 + 音轨，跑通再决定全量替换。
3. **WP2 P0 适配器**——把 TVBox/WebDAV/IPTV 包成协议实现，新架构先跑起来（不影响线上）。

> 以上三个可并行启动，互不阻塞。建议先确认 WP1 协议契约 + 是否接受 libmpv 技术路线，再全面铺开。
