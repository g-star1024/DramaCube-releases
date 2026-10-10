import Foundation
import CoreMedia
import QuartzCore
import Metal
import HongguoGatewayCore
import LibMPV

// MARK: - libmpv 播放引擎（M2 核心）
// 直接基于 LibMPV C API 自建控制器（MPVKit 的轨道枚举是占位，这里补全真实枚举）。
// 能力：全格式解码 / ASS·SSA 特效字幕 / 多音轨 / 倍速 / VideoToolbox 硬解 / HDR。

@MainActor
public final class MpvEngine: NSObject, PlaybackEngine, ObservableObject {
    public let kind: PlaybackEngineKind = .mpv

    // MARK: 发布状态
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isBuffering = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public var rate: Double = 1.0 { didSet { setDoubleAsync("speed", rate) } }
    @Published public var volume: Float = 1.0 { didSet { setDoubleAsync("volume", Double(volume * 100)) } }
    @Published public private(set) var error: String?
    @Published public private(set) var subtitleTracks: [SubtitleTrack] = []
    @Published public private(set) var audioTracks: [AudioTrack] = []
    @Published public private(set) var currentSubtitleID: String?
    @Published public private(set) var currentAudioID: String?
    @Published public private(set) var videoIsPortrait = false
    @Published public private(set) var hwDecoder: String = "unknown"

    // MARK: mpv 内部
    private var mpv: OpaquePointer?
    private var queue: DispatchQueue?
    /// 渲染目标（由 MpvVideoSurface 注入的 CAMetalLayer）。
    public var metalLayer = CAMetalLayer()
    private var pendingStart: TimeInterval?

    public override init() { super.init() }

    deinit { mpv_destroy(mpv) }

    // MARK: - 生命周期

    /// 创建 mpv 上下文并初始化渲染管线（Metal→MoltenVK→Vulkan→gpu-next）。
    private func setupIfNeeded() {
        guard mpv == nil else { return }
        mpv = mpv_create()
        guard mpv != nil else { error = "无法创建 mpv 上下文"; return }

        #if DEBUG
        mpv_request_log_messages(mpv, "warn")
        #else
        mpv_request_log_messages(mpv, "no")
        #endif
        mpv_set_property_string(mpv, "input-media-keys", "yes")

        // 字幕样式（ASS 由 libass 渲染，普通字幕给可读样式）
        mpv_set_property_string(mpv, "sub-font-size", "40")
        mpv_set_property_string(mpv, "sub-back-color", "0.0/0.0/0.0/0.75")
        mpv_set_property_string(mpv, "sub-border-size", "0")
        mpv_set_property_string(mpv, "sub-auto", "fuzzy")       // 自动加载同名字幕
        mpv_set_property_string(mpv, "sub-codepage", "auto")    // 编码嗅探（uchardet）

        // 缓存与起播
        mpv_set_property_string(mpv, "cache", "yes")
        mpv_set_property_string(mpv, "cache-pause-initial", "yes")
        mpv_set_property_string(mpv, "cache-pause-wait", "3")
        mpv_set_property_string(mpv, "keep-open", "yes")
        mpv_set_property_string(mpv, "demuxer-lavf-analyzeduration", "1")

        // 渲染：Metal layer → MoltenVK → Vulkan → gpu-next
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.framebufferOnly = true
        metalLayer.pixelFormat = .bgra8Unorm
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer)
        mpv_set_property_string(mpv, "vo", "gpu-next")
        mpv_set_property_string(mpv, "gpu-api", "vulkan")
        mpv_set_property_string(mpv, "gpu-context", "moltenvk")
        mpv_set_property_string(mpv, "hwdec", "videotoolbox")   // Apple 硬解
        mpv_set_property_string(mpv, "profile", "fast")
        // HDR / Dolby Vision 直通
        mpv_set_property_string(mpv, "target-colorspace-hint", "yes")

        guard mpv_initialize(mpv) >= 0 else { error = "mpv 初始化失败"; return }

        queue = DispatchQueue(label: "mpv.events")
        readEvents()
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 1, "core-idle", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 2, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 3, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 4, "track-list/count", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 5, "video-params/aspect", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 6, "paused-for-cache", MPV_FORMAT_FLAG)
    }

    // MARK: - PlaybackEngine

    public func load(source: PlaybackSource) {
        setupIfNeeded()
        guard mpv != nil else { return }
        error = nil
        pendingStart = source.startPosition

        // 请求头（Referer/UA/Cookie）注入 http-header-fields
        if !source.headers.isEmpty {
            let lines = source.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            setString("http-header-fields", lines)
        }

        var options: [String] = []
        if let start = source.startPosition, start > 0 {
            options.append("start=\(Int(start))")
        }
        // 外挂字幕
        for sub in source.subtitles where !sub.isEmbedded {
            if let u = sub.url { options.append("sub-files-append=\"\(u)\"") }
        }
        var args = [source.url.absoluteString, "replace"]
        if !options.isEmpty { args.append(options.joined(separator: ",")) }
        command("loadfile", args: args)
    }

    public func play() { isPlaying = true; setFlagAsync("pause", false) }
    public func pause() { isPlaying = false; setFlagAsync("pause", true) }
    public func togglePlayPause() { command("cycle", args: ["pause"]) }

    public func seek(to seconds: Double) {
        command("seek", args: [String(seconds), "absolute"])
    }
    public func seek(by delta: Double) {
        command("seek", args: [String(delta), "relative"])
    }
    public func stop() { command("stop") }

    public func selectSubtitle(id: String?) {
        currentSubtitleID = id
        setString("sid", id ?? "no")
    }
    public func selectAudio(id: String) {
        currentAudioID = id
        setString("aid", id)
    }

    // MARK: - 事件循环

    private func readEvents() {
        queue?.async { [weak self] in
            guard let self else { return }
            while self.mpv != nil {
                guard let event = mpv_wait_event(self.mpv, -1) else { continue }
                if event.pointee.event_id == MPV_EVENT_NONE { continue }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: UnsafePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_SHUTDOWN:
            mpv_destroy(mpv); mpv = nil
        case MPV_EVENT_FILE_LOADED:
            Task { @MainActor in
                self.refreshTracks()
                self.hwDecoder = self.getString("hwdec-current") ?? "unknown"
                if let s = self.pendingStart, s > 0 { self.seek(to: s); self.pendingStart = nil }
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            let dataOpaquePtr = OpaquePointer(event.pointee.data)
            if let prop = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
                handleProperty(prop)
            }
        case MPV_EVENT_VIDEO_RECONFIG:
            Task { @MainActor in self.updateOrientation() }
        case MPV_EVENT_END_FILE:
            Task { @MainActor in self.isPlaying = false }
        default:
            break
        }
    }

    private func handleProperty(_ prop: mpv_event_property) {
        let name = String(cString: prop.name)
        Task { @MainActor in
            switch name {
            case "pause":
                if let d = prop.data { self.isPlaying = d.load(as: Int32.self) == 0 }
            case "core-idle", "paused-for-cache":
                if let d = prop.data { self.isBuffering = d.load(as: Int32.self) != 0 }
            case "time-pos":
                if let d = prop.data { self.currentTime = d.load(as: Double.self) }
            case "duration":
                if let d = prop.data { self.duration = d.load(as: Double.self) }
            case "track-list/count":
                self.refreshTracks()
            case "video-params/aspect":
                self.updateOrientation()
            default:
                break
            }
        }
    }

    // MARK: - 轨道枚举（真实，从 track-list 读取）

    private func refreshTracks() {
        guard mpv != nil else { return }
        let count = getInt("track-list/count")
        var subs: [SubtitleTrack] = []
        var auds: [AudioTrack] = []
        for i in 0..<count {
            let type = getString("track-list/\(i)/type") ?? ""
            let id = getInt("track-list/\(i)/id")
            let title = getString("track-list/\(i)/title") ?? "轨道 \(id)"
            let lang = getString("track-list/\(i)/lang")
            let selected = getFlag("track-list/\(i)/selected")
            switch type {
            case "sub":
                let ext = getFlag("track-list/\(i)/external")
                subs.append(SubtitleTrack(id: "\(id)", title: title, language: lang,
                                          format: getString("track-list/\(i)/codec"),
                                          url: nil, isEmbedded: !ext))
                if selected { currentSubtitleID = "\(id)" }
            case "audio":
                auds.append(AudioTrack(id: "\(id)", title: title, language: lang,
                                       channels: getInt("track-list/\(i)/demux-channel-count")))
                if selected { currentAudioID = "\(id)" }
            default:
                break
            }
        }
        subtitleTracks = subs
        audioTracks = auds
    }

    private func updateOrientation() {
        let aspect = getDouble("video-params/aspect")
        videoIsPortrait = aspect > 0 && aspect < 1.0
    }

    // MARK: - C API 辅助

    private func command(_ cmd: String, args: [String?] = []) {
        guard mpv != nil else { return }
        var strArgs = args
        strArgs.insert(cmd, at: 0)
        strArgs.append(nil)
        var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer { for p in cargs where p != nil { free(UnsafeMutablePointer(mutating: p!)) } }
        mpv_command(mpv, &cargs)
    }

    private func setFlagAsync(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var d: Int32 = flag ? 1 : 0
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_FLAG, &d)
    }
    private func setDoubleAsync(_ name: String, _ value: Double) {
        guard mpv != nil else { return }
        var d = value
        mpv_set_property_async(mpv, 0, name, MPV_FORMAT_DOUBLE, &d)
    }
    private func setString(_ name: String, _ value: String) {
        guard mpv != nil else { return }
        mpv_set_property_string(mpv, name, value)
    }
    private func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0 }
        var d = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &d)
        return d
    }
    private func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var d = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &d)
        return Int(d)
    }
    private func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var d = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &d)
        return d > 0
    }
    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        let s: String? = cstr == nil ? nil : String(cString: cstr!)
        mpv_free(cstr)
        return s
    }
}
