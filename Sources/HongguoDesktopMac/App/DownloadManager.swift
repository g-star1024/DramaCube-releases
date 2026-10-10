import Foundation
import Combine
import AppKit

/// 视频下载任务状态。
public enum DownloadState: String, Codable, Sendable {
    case pending, downloading, merging, completed, failed, canceled
}

/// 单个下载任务。
public struct DownloadTask: Identifiable, Codable, Sendable {
    public let id: String              // dramaId|episodeId
    public var dramaTitle: String
    public var episodeTitle: String
    public var sourceURL: String       // 原始播放地址（m3u8/mp4，经网关代理的可直接访问）
    public var outputPath: String      // 输出 mp4 完整路径
    public var state: DownloadState
    public var progress: Double        // 0~1
    public var errorMessage: String?
    public var createdAt: Date
}

/// 下载管理器：m3u8 走 ffmpeg（自动处理分片/AES-128/合并转 mp4），mp4 直链走 URLSession 下载。
/// 并发由 maxConcurrent 控制；单任务内部 ffmpeg 自行多线程。
@MainActor
public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()
    private init() { loadTasks() }

    @Published public private(set) var tasks: [DownloadTask] = []
    @Published public var maxConcurrent: Int = 3 {
        didSet {
            UserDefaults.standard.set(maxConcurrent, forKey: "dl.maxConcurrent")
            if maxConcurrent != oldValue { schedule() }
        }
    }

    private var running: [String: Process] = [:]   // taskId -> ffmpeg process
    private var urlSessionTasks: [String: URLSessionDownloadTask] = [:]
    private var progressTimers: [String: Timer] = [:]

    // MARK: - 下载目录
    public static var downloadDir: URL {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("剧立方", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var tasksURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DramaCube", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("downloads.json")
    }

    public static var ffmpegPath: String? {
        for p in ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    // MARK: - 添加下载
    /// 添加下载任务。sourceURL 必须是可直接访问的地址（经网关代理或直链）。
    @discardableResult
    public func addDownload(dramaId: String, episodeId: String, dramaTitle: String,
                            episodeTitle: String, sourceURL: String) -> DownloadTask {
        let id = "\(dramaId)|\(episodeId)"
        if let existing = tasks.first(where: { $0.id == id }) {
            if existing.state == .completed || existing.state == .downloading { return existing }
        }
        let safeDrama = Self.sanitize(dramaTitle)
        let safeEp = Self.sanitize(episodeTitle)
        let out = Self.downloadDir.appendingPathComponent("\(safeDrama)/\(safeEp).mp4")
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let task = DownloadTask(id: id, dramaTitle: dramaTitle, episodeTitle: episodeTitle,
                                sourceURL: sourceURL, outputPath: out.path,
                                state: .pending, progress: 0, errorMessage: nil, createdAt: Date())
        tasks.removeAll { $0.id == id }
        tasks.insert(task, at: 0)
        persist()
        schedule()
        AppLog.log(.app, "添加下载：\(dramaTitle) \(episodeTitle)")
        return task
    }

    /// 是否已在下载/已下载。
    public func status(for dramaId: String, episodeId: String) -> DownloadState? {
        tasks.first(where: { $0.id == "\(dramaId)|\(episodeId)" })?.state
    }

    // MARK: - 调度
    private func schedule() {
        let runningCount = running.count + urlSessionTasks.count
        guard runningCount < maxConcurrent else { return }
        let pendings = tasks.filter { $0.state == .pending }.prefix(maxConcurrent - runningCount)
        for t in pendings { start(t) }
    }

    private func start(_ task: DownloadTask) {
        update(task.id) { $0.state = .downloading; $0.progress = 0; $0.errorMessage = nil }
        let lower = task.sourceURL.lowercased()
        let isDirectFile = lower.contains(".mp4") && !lower.contains("/api/")
        if isDirectFile {
            // mp4 直链：URLSession 直接下载（有真实文件大小，进度准确）
            runDirectDownload(task)
        } else if let ffmpeg = Self.ffmpegPath {
            // m3u8 / 网关代理流：ffmpeg 自动处理分片/AES-128/合并转 mp4
            runFFmpeg(task, ffmpeg: ffmpeg)
        } else {
            runDirectDownload(task)
        }
    }

    /// m3u8 / 代理地址：ffmpeg -i <url> -c copy out.mp4（自动分片/AES/合并转码）。
    private func runFFmpeg(_ task: DownloadTask, ffmpeg: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        var args = [
            "-y", "-hide_banner", "-loglevel", "error",
            "-user_agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            "-i", task.sourceURL,
        ]
        // 输出已是 mp4 容器（直链改后缀下载）时无需再转封装，仅重写时间戳即可。
        if task.outputPath.lowercased().hasSuffix(".mp4") {
            args += ["-c", "copy", "-bsf:a", "aac_adtstoasc"]
        } else {
            args += ["-c", "copy"]
        }
        args += ["-progress", "pipe:1", task.outputPath]
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        // 解析 -progress 输出更新进度（out_time_ms / total）
        let durationHint = estimateDurationSeconds(task)
        outPipe.fileHandleForReading.readabilityHandler = { [weak self, durationHint] fh in
            let line = String(data: fh.availableData, encoding: .utf8) ?? ""
            var latestProgress: Double?
            for l in line.split(separator: "\n") where l.hasPrefix("out_time_ms=") {
                if let us = Double(l.replacingOccurrences(of: "out_time_ms=", with: "")), durationHint > 0 {
                    latestProgress = min((us / 1_000_000) / durationHint, 0.99)
                }
            }
            if let latestProgress {
                let taskId = task.id
                Task { @MainActor [weak self] in
                    self?.update(taskId) { $0.progress = latestProgress }
                }
            }
        }
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.running[task.id] = nil
                self.progressTimers[task.id]?.invalidate(); self.progressTimers[task.id] = nil
                let ok = p.terminationStatus == 0 && FileManager.default.fileExists(atPath: task.outputPath)
                self.update(task.id) {
                    $0.state = ok ? .completed : .failed
                    $0.progress = ok ? 1 : $0.progress
                    $0.errorMessage = ok ? nil : "ffmpeg 退出码 \(p.terminationStatus)"
                }
                self.persist()
                self.schedule()
                if ok { AppLog.log(.app, "下载完成：\(task.dramaTitle) \(task.episodeTitle)") }
            }
        }
        do {
            try proc.run()
            running[task.id] = proc
        } catch {
            update(task.id) { $0.state = .failed; $0.errorMessage = "ffmpeg 启动失败：\(error.localizedDescription)" }
            persist(); schedule()
        }
    }

    /// mp4 直链：URLSession 下载。
    private func runDirectDownload(_ task: DownloadTask) {
        guard let url = URL(string: task.sourceURL) else {
            update(task.id) { $0.state = .failed; $0.errorMessage = "地址无效" }; persist(); schedule(); return
        }
        let dest = URL(fileURLWithPath: task.outputPath)
        let session = URLSession.shared
        let dt = session.downloadTask(with: url) { tmp, resp, err in
            Task { @MainActor in
                self.urlSessionTasks[task.id] = nil
                if let tmp, err == nil {
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.moveItem(at: tmp, to: dest)
                    self.update(task.id) { $0.state = .completed; $0.progress = 1 }
                } else {
                    self.update(task.id) { $0.state = .failed; $0.errorMessage = err?.localizedDescription ?? "下载失败" }
                }
                self.persist(); self.schedule()
            }
        }
        urlSessionTasks[task.id] = dt
        dt.resume()
        // 进度轮询
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let d = self.urlSessionTasks[task.id] else { return }
                let total = d.countOfBytesExpectedToReceive
                if total > 0 {
                    self.update(task.id) { $0.progress = Double(d.countOfBytesReceived) / Double(total) }
                }
            }
        }
        progressTimers[task.id] = timer
    }

    // MARK: - 控制
    public func cancel(_ taskId: String) {
        if let proc = running[taskId] { proc.terminate(); running[taskId] = nil }
        if let dt = urlSessionTasks[taskId] { dt.cancel(); urlSessionTasks[taskId] = nil }
        progressTimers[taskId]?.invalidate(); progressTimers[taskId] = nil
        update(taskId) { $0.state = .canceled }
        persist(); schedule()
    }

    public func remove(_ taskId: String) {
        cancel(taskId)
        if let t = tasks.first(where: { $0.id == taskId }) {
            try? FileManager.default.removeItem(atPath: t.outputPath)
        }
        tasks.removeAll { $0.id == taskId }
        persist()
    }

    public func reveal(_ taskId: String) {
        guard let t = tasks.first(where: { $0.id == taskId }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t.outputPath)])
    }

    // MARK: - 持久化与工具
    private func update(_ id: String, _ mutate: (inout DownloadTask) -> Void) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[i])
    }

    private func loadTasks() {
        maxConcurrent = UserDefaults.standard.object(forKey: "dl.maxConcurrent") == nil
            ? 3 : UserDefaults.standard.integer(forKey: "dl.maxConcurrent")
        if let data = try? Data(contentsOf: Self.tasksURL),
           let list = try? JSONDecoder().decode([DownloadTask].self, from: data) {
            // 重启后把 downloading/pending 重置回 pending 以便续下
            tasks = list.map {
                var t = $0
                if t.state == .downloading || t.state == .merging { t.state = .pending }
                return t
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: Self.tasksURL, options: .atomic)
        }
    }

    /// 文件名安全化（去掉路径分隔符与非法字符）。
    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "[/\\\\:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// m3u8 进度估算：暂无总时长时按 90 分钟电影估（ffmpeg -progress 只给已处理时长）。
    private func estimateDurationSeconds(_ task: DownloadTask) -> Double {
        // 短剧单集一般 1-3 分钟，用 180s 作分母能让进度条有反馈；转码完成时强制置 1。
        180
    }
}
