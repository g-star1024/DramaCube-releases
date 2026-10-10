# MoonTVPlus / 同类产品调研报告
——面向剧立方 DramaCube（macOS 原生 Swift + AVPlayer + 本地网关代理）

> 调研对象：MoonTVPlus（mtvpls/MoonTVPlus，3.4k★，TypeScript/Next.js 14）
> 参考同类：MoonTV（senshinya）、LunaTV（MoonTechLab）、aifeifei798/MoonTVPlus 分支
> 调研方式：克隆真实源码逐文件分析 + DeepWiki 架构文档 + 官方 README/博客交叉验证
> 日期：2026-10-10

---

## 0. 一句话总览

MoonTVPlus 是基于 MoonTV v100 的增强版，**纯 Web（浏览器）方案**：ArtPlayer（播放器壳）+ HLS.js（m3u8 解码）+ WebGPU（Anime4K 超分）+ Next.js API 代理（解决 CORS/防盗链/封面/下载）。它的核心套路对我们有 3 点可直接借鉴：**① m3u8 代理重写、② 封面多级回退代理、③ HLS.js 缓冲参数化**。

---

## 1. 视频解码方案

| 维度 | MoonTVPlus 做法 | 关键代码/库 |
|------|----------------|------------|
| 播放器壳 | **ArtPlayer**（轻量 HTML5 播放器，支持手势/快捷键/插件） | `artplayer` |
| m3u8 解码 | **HLS.js**（MSE 软解，把 m3u8 拆成 ts 分片喂给 `<video>`） | `hls.js` |
| FLV 流 | **FLV.js**（直播场景） | `flv.js` |
| 字幕 | artplayer-plugin-jassub（ASS/SSA） | `artplayer-plugin-jassub` |
| 超分 | **Anime4K**（WebGPU 实时 1.5x–4x 画质增强） | 自研 `lib/anime4k` |
| CORS/防盗链 | **Next.js API 代理** `/api/proxy-m3u8`、`/api/proxy/vod/m3u8`：服务端拉流重写 m3u8，把分片 URL 改写成走自家代理 | `src/app/api/proxy-m3u8/route.ts` |

### 关键洞察：m3u8 代理重写（和我们刚修的直播 bug 同款）
MoonTVPlus 明确区分两类代理：
- 直链可播（mp4/mkv）→ `source=directplay` 轻代理；
- m3u8 → **必须重写**：`episodeUrl = /api/proxy/vod/m3u8?url=<编码后>`，服务端解析 m3u8、把里面的分片/密钥 URL 全部改写成走代理，否则浏览器直接请求分片会被 CORS/Referer 拦。

> ✅ **对我们的借鉴**：这正是我们 v1.1.8 修的直播根因——AVPlayer 拿到未重写的 m3u8 会绕过网关直连分片，分片域名对 AVPlayer UA 防盗链导致播放失败。我们已实现同款 `rewriteM3U8`（分片/子列表/#EXT-X-KEY 的 URI 全改写走 `/api/live/stream`）。**这条路线被主流方案验证是对的**。

### 解码对我们的启示
- Web 端没有硬件解码，靠 MSE 软解；我们 macOS 原生用 **AVPlayer 硬解**，天然更省 CPU、支持 HEVC/4K，无需 Anime4K 这类软件超分。
- 若未来要做画质增强，macOS 上可考虑 **Metal 加速的实时滤镜**（而非 WebGPU Anime4K），但优先级低。

---

## 2. 调用系统/外部播放器

MoonTVPlus 通过 **URL scheme** 唤起本机外部播放器（直播页 `live/page.tsx` 实测）：

| 播放器 | URL scheme |
|--------|-----------|
| PotPlayer | `potplayer://<videoUrl>` |
| VLC | `vlc://<videoUrl>` |
| IINA（macOS） | `iina://weblink?url=<encodeURIComponent(videoUrl)>` |
| nPlayer | `nplayer-<videoUrl>` |
| MX Player（Android） | `intent:<url>#Intent;package=com.mxtech.videoplayer.ad;...` |
| MPV | `mpv://<videoUrl>` |

实现方式统一是 `window.open('<scheme>://<url>', '_blank')`——浏览器跳转到自定义 scheme，由 OS 分发给已安装的播放器。

### ✅ 对我们的可落地建议
我们是 **macOS 原生 App，不需要 scheme**，可以直接：
1. **调起 IINA/VLC**：用 `NSWorkspace.shared.open(URL(string: "iina://weblink?url=...")!)`，或更直接地 `NSWorkspace` 以指定 App 打开视频 URL（需播放器支持命令行/URL 接收）。
2. **更优**：用户既然装了我们的客户端，主诉求是内嵌播放。可把「在 IINA 中打开」做成**播放页的右键/菜单项**，给那些想要 IINA 高级字幕/滤镜的用户一个出口。成本低（几行代码），可作为增强项。
3. 命令行方式：`open -a IINA <url>` / `open -a VLC <url>`（通过 `Process` 调起），比 scheme 更可靠（不依赖播放器注册 scheme）。

---

## 3. 视频封面问题（重点）

这是同类产品最头疼、方案最分散的一块。MoonTVPlus 的策略是**「来源回退 + 防盗链代理 + 骨架屏占位」**三段式：

### 3.1 封面来源（多级回退）
1. **首选源站自带**：maccms API 返回的 `vod_pic`（采集站通常有，但质量参差、常失效）。
2. **豆瓣 API**：按标题+年份搜豆瓣，取豆瓣海报（`doubanio.com`，质量高但**防盗链**）。
3. **Bangumi（bgm.tv）**：动漫类走 Bangumi 封面（`lain.bgm.tv`）。
4. **TMDB**：海外内容走 TMDB（`lib/tmdb.search` 的 `getTMDBImageUrl`）。

代码里 `tryApplyDoubanImageFallback` / `tryApplyBangumiImageFallback`：主图加载失败时自动切换到回退源。

### 3.2 封面防盗链代理（`processImageUrl`）
豆瓣/采集站图片有 Referer 防盗链，MoonTVPlus 提供 **5 种代理模式**（用户可选）：
- `server`：自家 `/api/image-proxy?url=...`（服务端转发，最稳）；
- `img3`：直连豆瓣 `img3.doubanio.com`（部分域名不校验 Referer）；
- `cmliussss-cdn-tencent` / `cmliussss-cdn-ali`：第三方公益 CDN 反代豆瓣；
- `custom`：自建图片代理；
- `direct`：直连（看运气）。

并有 **主备双代理**（`backupProxyType`）：主代理挂了自动切备代理。

### 3.3 缺封面占位（`ImagePlaceholder`）
- **不是显示标题文字**，而是**骨架屏微光动画**：`linear-gradient` 横向扫光（`shine 1.5s infinite`），暗色模式适配。
- 图片加载失败也不显示破图，保持骨架/回退到下一张图。

> 注：MoonTVPlus **没有从视频流提取首帧做封面**——因为 Web 端 `<video>` 跨域无法 `canvas.drawImage` 截图（会污染 canvas），成本高。它选择「多级图片源回退」规避。

### ✅ 对我们的可落地建议（封面）
我们 macOS 原生 + 有本地网关，**比 Web 方案多一张王牌：可以从视频流抽首帧**。分三层做：

1. **占位样式**（已做 ✅）：v1.1.5 已改成「暖沙底渐变 + 居中播放图标」，比 MoonTVPlus 的骨架屏更贴合品牌，保留即可。
2. **图片源回退**（建议做）：源站 `vod_pic` 失效时，回退**豆瓣封面**——按标题（去集数/年份干扰）调豆瓣搜索 API（`https://api.douban.com/v2/search` 或抓 `www.douban.com/search`），取第一张海报，经我们**网关 `/api/image-proxy` 代理**（解决豆瓣 Referer 防盗链）。这是性价比最高的一招，能救回大量失效封面。
3. **首帧截图**（终极方案，可选）：对**本地 NAS 资源库**（无封面的个人视频），用 `AVAssetImageGenerator` 抽第 1~3 秒首帧生成缩略图缓存到本地——这是原生方案独有的优势，Web 做不到。短剧源站一般有封面，NAS 才是缺封面重灾区，建议优先给 NAS 加。

---

## 4. 下载设置

MoonTVPlus 有**两套下载**，对应不同部署形态：

### 4.1 服务器端离线下载（`lib/offline-downloader.ts`，自托管 Docker）
- 服务端 Node.js 直接下 m3u8：解析出 ts 分片 → **并发 6 线程**下载（`concurrency = 6`）→ 存本地文件系统（`segment_00000.ts`...）；
- **断点续传**：已存在且 size>0 的分片跳过；
- **AES-128 解密**：解析 `#EXT-X-KEY`，下载密钥解密分片；
- **重试**：每分片 3 次指数退避；
- **合并**：生成 `playlist.m3u8` 指向本地分片（不转码成 mp4，保留 ts+m3u8 结构，靠播放器本地播）。

### 4.2 浏览器端下载（`lib/m3u8-downloader.ts` + `contexts/DownloadContext.tsx`）
对应你截图的「下载设置」：
- **下载模式**：
  - **浏览器下载（合并单文件）**：分片下载后在内存/Blob 合并成单个 ts，触发浏览器保存；
  - **File System API（分片存本地目录）**：`showSaveFilePicker` / `createWritable`（`m3u8-downloader.ts:987`），边下边写本地目录，生成 `playlist.m3u8` + 分片，不合并；
- **最大同时下载数**：控制并发任务（你截图的 1~10 个滑块）；
- **单任务线程数**：每任务的分片并发（1~32，你截图的 6 个）。

> 它**没有 ffmpeg.wasm 转码**——保留 ts 不转 mp4（省 CPU、快，代价是兼容性差些）。

### ✅ 对我们的可落地建议（下载）
我们是原生 App，下载比 Web 简单强大得多：
- 用 `URLSessionDownloadTask` 或 `URLSession.bytes` 直接下 ts 分片，**并发用 `TaskGroup` 限流**（参考 MoonTVPlus 的 6 并发）；
- **断点续传**：分片落盘，已存在跳过；
- **AES-128**：`CommonCrypto` 解密 `#EXT-X-KEY`；
- **合并**：可直接 `ffmpeg` 命令行（`Process` 调 `ffmpeg -i playlist.m3u8 -c copy out.mp4`）转 mp4——比 Web 的 ffmpeg.wasm 快几十倍；
- 设置项可照搬：最大同时下载数、单任务线程数两个滑块。
- **优先级**：这是个较大功能，建议确认要做再排期（非本次必需）。

---

## 5. 缓存 / 缓冲设置

对应你截图的「缓冲设置」。MoonTVPlus 是**纯 HLS.js 参数化**（`play/page.tsx:7816-7878`）：

| 缓冲策略 | `maxBufferLength`（前向缓冲秒） | `backBufferLength`（已播保留秒） |
|---------|------|------|
| 低缓冲 | 15 | 15 |
| 中缓冲（推荐） | 30 | 30 |
| 高缓冲 | 60 | 40 |
| 超高缓冲 | 120 | 60 |

- `bufferStrategy` 存 localStorage，播放器初始化时读；
- **下集预缓冲**：播放进度达 90% 时预加载下一集的 m3u8（预解析+预取前几个分片，不切流）。

### ✅ 对我们的可落地建议（缓冲）
AVPlayer **不暴露 HLS.js 那样的秒级缓冲参数**，但有等价手段：
1. **预加载时长**：`AVPlayerItem.preferredForwardBufferDuration = <秒>`（等价 maxBufferLength）——可做成设置项：低/中/高/超高 = 15/30/60/120 秒，**这是最值得抄的一条**。
2. **下集预缓冲**：播放进度 90% 时，后台 `AVAsset(url: 下一集代理地址)` 预热（`loadValuesAsynchronously`），或提前创建 `AVPlayerItem` 备用——和 MoonTVPlus 思路一致，实现不难。
3. **已播保留**：AVPlayer 自动管理，无需手动 backBufferLength。
4. **网络自适应**：AVPlayer 自带 HLS 自适应码率（ABR），比 HLS.js 默认策略更省心。

---

## 6. 总结：对剧立方的可落地清单（按性价比排序）

| 优先级 | 功能 | 借鉴点 | 落地成本 | 状态 |
|------|------|--------|---------|------|
| ⭐⭐⭐ | **m3u8 代理重写** | 分片 URL 全走网关 | 已完成 | ✅ v1.1.8 |
| ⭐⭐⭐ | **封面占位优化** | 暖沙底+播放图标（比骨架屏更品牌） | 已完成 | ✅ v1.1.5 |
| ⭐⭐⭐ | **豆瓣封面回退** | 源站图失效→豆瓣海报→网关 image-proxy 防盗链 | 中（半天） | 建议做 |
| ⭐⭐ | **缓冲策略设置** | `preferredForwardBufferDuration` 15/30/60/120s | 低（1-2h） | 建议做 |
| ⭐⭐ | **下集预缓冲** | 90% 进度预创建下一集 AVPlayerItem | 低 | 建议做 |
| ⭐⭐ | **NAS 首帧封面** | `AVAssetImageGenerator` 抽首帧（原生独有） | 中 | 可选 |
| ⭐ | **在 IINA/VLC 打开** | `open -a IINA <url>` 右键出口 | 极低 | 可选增强 |
| ⭐ | **视频下载** | ts 分片并发下载+ffmpeg 转 mp4+断点续传 | 高（1-2天） | 确认后做 |

### 核心结论
1. 我们**架构方向是对的**：本地网关代理 + m3u8 重写，和 MoonTVPlus 这类成熟 Web 方案的代理套路完全一致，且原生 AVPlayer 硬解比 Web MSE 软解更强。
2. **封面**是最值得继续投入的一块：豆瓣回退 + NAS 首帧，能覆盖 90% 缺封面场景。
3. **缓冲/预缓冲**用 `preferredForwardBufferDuration` + 预创建 item 就能低成本复刻 MoonTVPlus 的体验。
4. **下载**是大功能，建议单独立项，技术上原生方案（URLSession + ffmpeg）比 Web 简单且快。

---

*调研源码版本：mtvpls/MoonTVPlus @ 2026-10（clone --depth 1）*
