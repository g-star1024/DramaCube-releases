import Foundation
import Darwin.Mach

/// 统一文件日志（v1.0.6）。
///
/// 写入 `~/Library/Logs/DramaCube/dramacube-YYYYMMDD.log`（每天一个文件，超 8MB 自动滚动，
/// 保留最近 7 天）。同时在 debug 构建下输出到控制台。
///
/// 分类：
///  - app：生命周期 / 网关 / 看门狗 / 内存
///  - net：网关与外网请求（起止、状态、字节数）
///  - player：选集 / 起播 / 就绪 / 失败 / 卡顿时长 / 关闭
///  - error：所有错误统一收口
public enum AppLog {
    public enum Category: String {
        case app, net, player, error
    }

    private static let queue = DispatchQueue(label: "com.dramacube.log", qos: .utility)
    nonisolated(unsafe) private static var currentFileName = ""
    nonisolated(unsafe) private static var fileHandle: FileHandle?

    /// 日志目录（暴露给「在 Finder 中显示」）。
    public static var logDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/DramaCube", isDirectory: true)
    }

    /// 当前日志文件路径（暴露给设置页展示）。
    public static var currentLogFile: URL {
        logDirectory.appendingPathComponent(fileName(for: Date()))
    }

    private static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "dramacube-\(f.string(from: date)).log"
    }

    public static func log(_ category: Category, _ message: @autoclosure () -> String) {
        let msg = message()
        let ts = timestamp()
        let line = "[\(ts)] [\(category.rawValue.uppercased())] \(msg)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        queue.async {
            write(line)
        }
    }

    // MARK: - 内部

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private static func write(_ line: String) {
        prepareFileIfNeeded()
        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private static func prepareFileIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let name = fileName(for: Date())
        if name != currentFileName {
            fileHandle?.closeFile()
            fileHandle = nil
            currentFileName = name
            pruneOldLogs()
        }

        let path = logDirectory.appendingPathComponent(name).path
        if fileHandle == nil {
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil)
            }
            fileHandle = FileHandle(forWritingAtPath: path)
            fileHandle?.seekToEndOfFile()
        }

        // 超 8MB 滚动：改名加 -HHmmss 后缀，重新开新文件
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > 8 << 20 {
            fileHandle?.closeFile()
            fileHandle = nil
            let f = DateFormatter()
            f.dateFormat = "HHmmss"
            let rolled = logDirectory.appendingPathComponent(name.replacingOccurrences(of: ".log", with: "-\(f.string(from: Date())).log"))
            try? fm.moveItem(at: URL(fileURLWithPath: path), to: rolled)
            fm.createFile(atPath: path, contents: nil)
            fileHandle = FileHandle(forWritingAtPath: path)
        }
    }

    /// 只保留最近 7 天的日志。
    private static func pruneOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for url in files where url.lastPathComponent.hasPrefix("dramacube-") {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod < cutoff { try? fm.removeItem(at: url) }
        }
    }
}

/// 主线程看门狗 + 内存心跳（v1.0.6）。
///
/// 每 1s 向主线程投递一个探针并记录投递时间；后台线程 1.5s 后检查探针是否被执行。
/// 若主线程超过 2s 未响应，记录一次卡顿（含持续时长）——这是定位「打开久了卡死」的关键证据。
/// 同时每 30s 记录一次常驻内存，观察是否单调上涨（泄漏判别）。
public enum Watchdog {
    nonisolated(unsafe) private static var started = false
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastPing = Date()

    public static func start() {
        guard !started else { return }
        started = true
        lastPing = Date()

        // 探针：每 1s ping 一次主线程
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let sent = Date()
            DispatchQueue.main.async {
                lock.lock()
                lastPing = sent
                lock.unlock()
            }
        }

        // 检查：每 1.5s 看主线程上次响应距今多久
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            lock.lock()
            let lag = Date().timeIntervalSince(lastPing)
            lock.unlock()
            if lag > 2.0 {
                AppLog.log(.app, "⚠️ 主线程无响应 \(String(format: "%.1f", lag))s（疑似卡顿/卡死）")
            }
        }

        // 内存心跳：每 30s
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            AppLog.log(.app, "内存常驻 \(residentMemoryMB()) MB")
        }
        AppLog.log(.app, "看门狗已启动")
    }

    private static func residentMemoryMB() -> Int {
        // 用 proc_pid_rusage 取物理 footprint，绕开 mach_task_self_ 的 Swift 6 并发诊断。
        var usage = rusage_info_current()
        let pid = ProcessInfo.processInfo.processIdentifier
        let ret = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard ret == 0 else { return -1 }
        return Int(usage.ri_resident_size >> 20)
    }
}
