import SwiftUI

/// 下载管理面板：任务列表（封面缩略图 + 剧名/集名 + 进度/状态 + 操作），对齐历史列表行样式。
struct DownloadsView: View {
    @ObservedObject private var dm = DownloadManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if dm.tasks.isEmpty {
                EmptyState("暂无下载任务", systemImage: "arrow.down.circle",
                           description: "在播放页点下载按钮即可下载当前集（m3u8 自动转 mp4）")
            } else {
                List {
                    ForEach(dm.tasks) { t in
                        DownloadRow(task: t)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Brand.background)
        .navigationTitle("下载")
    }
}

/// 单条下载任务行：状态缩略块 + 剧名/集名 + 进度条/错误 + 右侧操作按钮。
private struct DownloadRow: View {
    @ObservedObject private var dm = DownloadManager.shared
    let task: DownloadTask

    var body: some View {
        HStack(spacing: Spacing.md) {
            // 缩略块：完成=封面文件存在显示图标，否则按状态着色（对齐历史列表 60x84 缩略图位）
            thumb
                .frame(width: 60, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(task.dramaTitle).font(Typography.body).foregroundStyle(Brand.label).lineLimit(1)
                Text(task.episodeTitle).font(Typography.caption).foregroundStyle(Brand.secondaryLabel).lineLimit(1)

                switch task.state {
                case .downloading, .merging:
                    ProgressView(value: task.progress).tint(Brand.accent)
                    Text(task.state == .merging ? "合并转码中…" : "下载中 \(Int(task.progress * 100))%")
                        .font(.caption2).foregroundStyle(Brand.secondaryLabel)
                case .completed:
                    Text("已完成 · \(fileSizeText)").font(.caption2).foregroundStyle(.green)
                case .failed:
                    Text(task.errorMessage ?? "下载失败").font(.caption2).foregroundStyle(.red).lineLimit(2)
                case .pending:
                    Text("排队等待中").font(.caption2).foregroundStyle(Brand.secondaryLabel)
                case .canceled:
                    Text("已取消").font(.caption2).foregroundStyle(Brand.secondaryLabel)
                }

                Text(HongguoFormat.relative(task.createdAt))
                    .font(.caption2).foregroundStyle(Brand.secondaryLabel)
            }
            Spacer()

            HStack(spacing: Spacing.sm) {
                if task.state == .completed {
                    Button("打开") { dm.reveal(task.id) }.controlSize(.small)
                }
                if task.state == .downloading || task.state == .pending {
                    Button("取消") { dm.cancel(task.id) }.controlSize(.small)
                }
                if task.state == .failed || task.state == .canceled {
                    Button("重试") { retry() }.controlSize(.small)
                }
                Button(role: .destructive) { dm.remove(task.id) } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    /// 状态缩略块（替代封面：下载源地址无独立封面，用 SF Symbol + 状态色块）。
    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(thumbColor.opacity(0.12))
            Image(systemName: thumbIcon)
                .font(.system(size: 24))
                .foregroundStyle(thumbColor)
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(thumbColor.opacity(0.3), lineWidth: 0.5))
    }

    private var thumbIcon: String {
        switch task.state {
        case .completed: return "checkmark.circle.fill"
        case .downloading, .merging: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .canceled: return "xmark.circle"
        case .pending: return "clock.fill"
        }
    }
    private var thumbColor: Color {
        switch task.state {
        case .completed: return .green
        case .downloading, .merging: return Brand.accent
        case .failed: return .red
        default: return Brand.secondaryLabel
        }
    }

    private var fileSizeText: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: task.outputPath),
              let size = attrs[.size] as? Int64 else { return "" }
        let mb = Double(size) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    private func retry() {
        dm.remove(task.id)
        dm.addDownload(dramaId: task.id.split(separator: "|").first.map(String.init) ?? task.id,
                       episodeId: task.id.split(separator: "|").last.map(String.init) ?? "",
                       dramaTitle: task.dramaTitle, episodeTitle: task.episodeTitle, sourceURL: task.sourceURL)
    }
}
