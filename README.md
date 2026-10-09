# 红果短剧桌面版 · macOS 客户端

> 红果短剧桌面版的 **macOS 原生客户端**（macOS 13 Ventura+，Intel x86_64 / Apple Silicon 通用二进制）。
> 采用 SwiftUI + AppKit 原生壳，Hummingbird 本地网关统一收口内容接入，AVPlayer 播放。

---

## 一、双仓策略（重要）

| 仓库 | 性质 | 内容 |
|------|------|------|
| [`g-star1024/hongguo-desktop`](https://github.com/g-star1024/hongguo-desktop) | **私有** | 全部**源码**（Swift 工程、网关、文档、脚本） |
| [`g-star1024/hongguo-desktop-releases`](https://github.com/g-star1024/hongguo-desktop-releases) | **公开** | 仅**发布产物**：安装包 `.dmg`/`.zip`、`latest.json`、README、截图（与 Windows 版同结构） |

源码不公开，客户端构建产物公开分发。发布流程见 `Scripts/build-release.sh`。

## 二、技术栈

- **语言**：Swift 6（Swift 6.0.3 / Xcode 16.2 验证）
- **UI**：SwiftUI + AppKit（NavigationSplitView、Settings scene、原生菜单/快捷键）
- **本地网关**：[Hummingbird 2](https://github.com/hummingbird-project/hummingbird)（Swift 原生 HTTP 服务，监听 `127.0.0.1:8787`）
- **HTML 解析**：[SwiftSoup](https://github.com/scinfu/SwiftSoup)
- **播放**：AVPlayer / AVKit（VideoPlayer）
- **包管理**：Swift Package Manager
- **目标**：macOS 13.0+，Universal Binary（`arm64 + x86_64`）

## 三、内容接入架构

Windows 版是 WebView2 + Python(FastAPI) 本地服务的闭源壳。本 Mac 版**不复制其二进制**，而是从公开网页接口重建：

```
SwiftUI App ──HTTP──> 本地网关(Hummingbird :8787) ──HTTPS(剥离 Referer)──> novelquickapp.com / 字节 CDN
```

- **浏览 / 搜索 / 榜单 / 详情**：解析 `novelquickapp.com` 分享落地页内联的 `window._ROUTER_DATA`（列表类接口免签名）。
- **播放**：取解析出的 `play_url` 直链，网关代理请求 CDN 时**统一不携带 Referer**（字节 CDN 对带 Referer 返回 403）。
- 不依赖任何逆向签名（X-Argus / spade_a），无需设备仿真或私有密钥。

> 调研细节见 `.workbuddy/analysis/api-research-2026-10-09.md`。

## 四、目录结构

```
hongguo-desktop/
├── Package.swift                 # SPM 工程（Xcode 16 可直接打开）
├── Sources/
│   ├── HongguoCore/              # 模型 + 网页解析 + HTTP 客户端（可被 App 与网关共用）
│   ├── HongguoGateway/           # Hummingbird 本地网关可执行（swift run 启动）
│   └── HongguoDesktopMac/        # SwiftUI App 源码（作为库，由 Xcode App Target 引用）
├── Tests/HongguoCoreTests/
├── Scripts/
│   ├── dev.sh                    # 本地开发：起网关 + 开 Xcode
│   └── build-release.sh          # 构建通用二进制 + 打包 + 发布到 releases 仓
└── Documentation/
```

## 五、本地开发

### 方式 A：Xcode（推荐，可跑完整 App）

1. `open Package.swift`（Xcode 16 直接以 SPM 工程打开，获得代码补全/预览）。
2. `File ▸ New ▸ Target ▸ macOS ▸ App`，命名 `HongguoDesktopMacApp`，嵌入 `HongguoCore` 与 `HongguoDesktopMac` 库。
3. 把自动生成的 `HongguoDesktopMacAppApp.swift` 改为：
   ```swift
   import SwiftUI
   import HongguoDesktopMac
   @main
   struct Runner: App { var body: some Scene { HongguoApp().body } }
   ```
4. 首次运行前启动本地网关（见方式 B），或在 `Runner` 中通过 `Process` 捆绑启动 `HongguoGateway`。

### 方式 B：仅验证网关（命令行）

```bash
swift build
swift run HongguoGateway        # 监听 http://127.0.0.1:8787
curl "http://127.0.0.1:8787/api/health"
curl "http://127.0.0.1:8787/api/search?q=关键词"
curl "http://127.0.0.1:8787/api/detail/<分享ID>"
```

## 六、构建与发布

```bash
export GITHUB_TOKEN=你的PAT        # 用于上传到 releases 仓
./Scripts/build-release.sh          # 产出 .dmg/.zip + latest.json 并发布
```

具体步骤见脚本内注释。需要 Apple Developer ID 签名 + notarization 才能免 Gatekeeper 警告（见 `Documentation/`）。

## 七、合规说明

本项目为**个人学习/研究用途的第三方客户端**，不托管任何影视内容，所有数据来自公开网页接口；
不破解、不 redistribution 红果/字节跳动的专有代码或资源。请遵守所在地法律法规与服务提供方条款。
