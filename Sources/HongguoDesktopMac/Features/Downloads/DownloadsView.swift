import SwiftUI

/// 下载管理面板：任务列表（进度/状态）+ 操作（取消/删除/打开目录）。
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
                        row(t)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Brand.background)
        .navigationTitle("下载")
    }

    private func row(_ t: DownloadTask) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon(for: t.state))
                .font(.system(size: 22))
                .foregroundStyle(color(for: t.state))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(t.dramaTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(t.episodeTitle).font(.system(size: 11)).foregroundStyle(Brand.secondaryLabel).lineLimit(1)
                if t.state == .downloading {
                    ProgressView(value: t.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                    Text("\(Int(t.progress * 100))%").font(.system(size: 10)).foregroundStyle(Brand.secondaryLabel)
                } else if let err = t.errorMessage, t.state == .failed {
                    Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: Spacing.sm) {
                if t.state == .completed {
                    Button("打开") { dm.reveal(t.id) }.controlSize(.small)
                }
                if t.state == .downloading || t.state == .pending {
                    Button("取消") { dm.cancel(t.id) }.controlSize(.small)
                }
                if t.state == .failed {
                    Button("重试") { retry(t) }.controlSize(.small)
                }
                Button("删除") { dm.remove(t.id) }.controlSize(.small).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func retry(_ t: DownloadTask) {
        dm.remove(t.id)
        dm.addDownload(dramaId: t.id.split(separator: "|").first.map(String.init) ?? t.id,
                       episodeId: t.id.split(separator: "|").last.map(String.init) ?? "",
                       dramaTitle: t.dramaTitle, episodeTitle: t.episodeTitle, sourceURL: t.sourceURL)
    }

    private func icon(for s: DownloadState) -> String {
        switch s {
        case .completed: return "checkmark.circle.fill"
        case .downloading, .merging: return "arrow.down.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .canceled: return "xmark.circle"
        case .pending: return "clock"
        }
    }
    private func color(for s: DownloadState) -> Color {
        switch s {
        case .completed: return .green
        case .downloading, .merging: return Brand.accent
        case .failed: return .red
        default: return Brand.secondaryLabel
        }
    }
}
