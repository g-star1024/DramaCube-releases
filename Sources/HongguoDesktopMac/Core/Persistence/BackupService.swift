import Foundation
import SwiftData
import AppKit
import HongguoCore

/// 本地数据备份 / 恢复服务（设置中心「数据备份」分组）。
///
/// 导出范围：AppSettings（UserDefaults）+ 收藏 + 历史/播放进度 + 视频源配置 + 直播源配置 + NAS 资源库配置。
/// 格式：单个 JSON 文件（.dramacube-backup），导入时按 key 合并（不存在的 key 跳过，不覆盖未导出的项）。
@MainActor
public final class BackupService {
    public static let shared = BackupService()
    private init() {}

    // MARK: - 导出

    /// 导出全部本地数据到指定文件（NSSavePanel 选路径）。
    public func exportToFile() async throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dramacube-backup-\(dateStamp()).json"
        panel.message = "选择备份文件保存位置"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw BackupError.cancelled
        }
        try await export(to: url)
        return url
    }

    /// 导出到指定 URL（供自动化 / 测试直接调用）。
    public func export(to url: URL) async throws {
        let payload = BackupPayload(
            version: 1,
            exportedAt: Date(),
            appVersion: AppConfig.appVersion,
            settings: exportSettings(),
            favorites: exportFavorites(),
            history: exportHistory(),
            sources: exportSources(),
            live: exportLive(),
            nas: exportNAS()
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(payload)
        try data.write(to: url, options: Data.WritingOptions.atomic)
        AppLog.log(.app, "备份导出完成：\(url.path)（设置 \(payload.settings.count) 项 / 收藏 \(payload.favorites.count) / 历史 \(payload.history.count)）")
    }

    // MARK: - 导入

    /// 从文件导入（NSOpenPanel 选文件）。
    public func importFromFile() async throws -> URL {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "选择备份文件"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw BackupError.cancelled
        }
        try await importFrom(url)
        return url
    }

    /// 从指定 URL 导入（按 key 合并，不覆盖未导出的项）。
    public func importFrom(_ url: URL) async throws {
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let payload = try dec.decode(BackupPayload.self, from: data)
        guard payload.version <= 1 else {
            throw BackupError.unsupportedVersion(payload.version)
        }
        importSettings(payload.settings)
        try await importFavorites(payload.favorites)
        try await importHistory(payload.history)
        importSources(payload.sources)
        await importLive(payload.live)
        await importNAS(payload.nas)
        AppLog.log(.app, "备份导入完成：设置 \(payload.settings.count) 项 / 收藏 \(payload.favorites.count) / 历史 \(payload.history.count)")
    }

    // MARK: - 各项导出

    private func exportSettings() -> [String: String] {
        // UserDefaults 全量导出（值统一转字符串，导入时按原类型解析）
        var out: [String: String] = [:]
        for (k, v) in UserDefaults.standard.dictionaryRepresentation() {
            if let s = v as? String { out[k] = s }
            else if let b = v as? Bool { out[k] = b ? "true" : "false" }
            else if let i = v as? Int { out[k] = String(i) }
            else if let d = v as? Double { out[k] = String(d) }
            else if let f = v as? Float { out[k] = String(f) }
        }
        return out
    }

    private func exportFavorites() -> [FavoriteBackup] {
        Repository.shared.favorites().map {
            FavoriteBackup(dramaId: $0.dramaId, title: $0.title, coverURL: $0.coverURL, addedAt: $0.addedAt)
        }
    }

    private func exportHistory() -> [HistoryBackup] {
        Repository.shared.history().map {
            HistoryBackup(dramaId: $0.dramaId, episodeId: $0.episodeId, title: $0.title,
                          episodeTitle: $0.episodeTitle, coverURL: $0.coverURL,
                          position: $0.position, duration: $0.duration, updatedAt: $0.updatedAt)
        }
    }

    private func exportSources() -> SourcesBackup {
        let sm = SourceManager.shared
        return SourcesBackup(
            subscriptionURL: sm.subscriptionURL,
            disabled: Array(sm.disabled),
            manualDisabled: Array(sm.manualDisabled),
            currentSource: sm.currentSource
        )
    }

    private func exportLive() -> LiveBackup {
        let lm = LiveManager.shared
        return LiveBackup(
            sources: lm.sources.map { LiveSourceBackup(id: $0.id, url: $0.url, name: $0.name, enabled: $0.enabled, userAgent: $0.userAgent) }
        )
    }

    private func exportNAS() -> NASBackup {
        let nm = NASManager.shared
        return NASBackup(
            libraries: nm.libraries.map {
                NASLibraryBackup(id: $0.id, name: $0.name, type: $0.type.rawValue, baseURL: $0.baseURL,
                                 username: $0.username, password: $0.password, enabled: $0.enabled)
            },
            lastLibId: UserDefaults.standard.string(forKey: "nas.lastLibId")
        )
    }

    // MARK: - 各项导入

    private func importSettings(_ dict: [String: String]) {
        for (k, v) in dict {
            // 跳过系统内部 key（避免污染）
            if k.hasPrefix("NS") || k.hasPrefix("Apple") || k.hasPrefix("com.apple") { continue }
            // 按当前已存值的类型解析（无已存值则按字符串写入）
            let existing = UserDefaults.standard.object(forKey: k)
            if existing is Bool { UserDefaults.standard.set(v == "true", forKey: k) }
            else if existing is Int { UserDefaults.standard.set(Int(v) ?? 0, forKey: k) }
            else if existing is Double { UserDefaults.standard.set(Double(v) ?? 0, forKey: k) }
            else if existing is Float { UserDefaults.standard.set(Float(v) ?? 0, forKey: k) }
            else { UserDefaults.standard.set(v, forKey: k) }
        }
    }

    private func importFavorites(_ items: [FavoriteBackup]) async throws {
        for b in items {
            if !Repository.shared.isFavorite(dramaId: b.dramaId) {
                Repository.shared.toggleFavorite(dramaId: b.dramaId, title: b.title, coverURL: b.coverURL)
            }
        }
    }

    private func importHistory(_ items: [HistoryBackup]) async throws {
        for b in items {
            Repository.shared.saveProgress(dramaId: b.dramaId, episodeId: b.episodeId,
                                           title: b.title, episodeTitle: b.episodeTitle,
                                           coverURL: b.coverURL, position: b.position, duration: b.duration)
        }
    }

    private func importSources(_ b: SourcesBackup) {
        let sm = SourceManager.shared
        sm.subscriptionURL = b.subscriptionURL
        sm.currentSource = b.currentSource
        // disabled/manualDisabled 是 private(set)，但其 didSet 写 UserDefaults——直接写 UserDefaults 恢复，
        // 下次启动 SourceManager init 时从 UserDefaults 读回（见 SourceManager.swift L53-L59）
        UserDefaults.standard.set(b.disabled, forKey: "src.disabled")
        UserDefaults.standard.set(b.manualDisabled, forKey: "src.manualDisabled")
    }

    private func importLive(_ b: LiveBackup) async {
        let lm = LiveManager.shared
        for s in b.sources {
            _ = try? await lm.add(url: s.url, name: s.name, userAgent: s.userAgent)
            if !s.enabled { await lm.setEnabled(id: s.id, false) }
        }
    }

    private func importNAS(_ b: NASBackup) async {
        let nm = NASManager.shared
        for lib in b.libraries {
            _ = try? await nm.add(name: lib.name, type: NASManager.NASLibrary.LibType(rawValue: lib.type) ?? .webdav,
                                  base: lib.baseURL, user: lib.username, pass: lib.password)
            if !lib.enabled { await nm.setEnabled(id: lib.id, false) }
        }
        if let id = b.lastLibId { UserDefaults.standard.set(id, forKey: "nas.lastLibId") }
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // MARK: - 错误

    public enum BackupError: LocalizedError {
        case cancelled
        case unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .cancelled: return "已取消"
            case .unsupportedVersion(let v): return "备份文件版本 v\(v) 过新，当前应用不支持"
            }
        }
    }
}

// MARK: - 备份数据结构

private struct BackupPayload: Codable {
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var settings: [String: String]
    var favorites: [FavoriteBackup]
    var history: [HistoryBackup]
    var sources: SourcesBackup
    var live: LiveBackup
    var nas: NASBackup
}

private struct FavoriteBackup: Codable {
    var dramaId: String
    var title: String
    var coverURL: String?
    var addedAt: Date
}

private struct HistoryBackup: Codable {
    var dramaId: String
    var episodeId: String
    var title: String
    var episodeTitle: String
    var coverURL: String?
    var position: Double
    var duration: Double
    var updatedAt: Date
}

private struct SourcesBackup: Codable {
    var subscriptionURL: String
    var disabled: [String]
    var manualDisabled: [String]
    var currentSource: String
}

private struct LiveBackup: Codable {
    var sources: [LiveSourceBackup]
}

private struct LiveSourceBackup: Codable {
    var id: String
    var url: String
    var name: String
    var enabled: Bool
    var userAgent: String?
}

private struct NASBackup: Codable {
    var libraries: [NASLibraryBackup]
    var lastLibId: String?
}

private struct NASLibraryBackup: Codable {
    var id: String
    var name: String
    var type: String
    var baseURL: String
    var username: String?
    var password: String?
    var enabled: Bool
}
