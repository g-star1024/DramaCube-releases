import SwiftUI
import HongguoCore

/// NAS 资源库浏览页：库 chips + 路径导航 + 视频网格。
///
/// 库内目录（含视频）聚合为一部剧（多集），散文件逐文件成剧；
/// Drama.id = nas|<libId>|dir|<path> / nas|<libId>|file|<path>，详情/播放在 DetailView 按前缀分流。
struct NASBrowseView: View {
    @ObservedObject var nm: NASManager
    let onSelect: (Drama) -> Void

    @State private var currentLibId: String?
    @State private var currentPath: String = ""
    @State private var items: [Drama] = []
    @State private var isLoading = false
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            libBar
            if currentLibId != nil { pathBar }
            Divider()
            content
        }
        .background(Brand.background)
        .task {
            nm.load()
            // 默认选第一个启用的库
            if currentLibId == nil {
                currentLibId = nm.libraries.first(where: { $0.enabled })?.id ?? nm.libraries.first?.id
            }
            await load()
        }
        .onChange(of: currentLibId) { _, _ in currentPath = ""; Task { await load() } }
        .onChange(of: nm.libraries) { _, libs in
            if currentLibId == nil || !libs.contains(where: { $0.id == currentLibId }) {
                currentLibId = libs.first(where: { $0.enabled })?.id ?? libs.first?.id
                Task { await load() }
            }
        }
    }

    // MARK: 库切换条
    private var libBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(nm.libraries) { lib in
                    let active = currentLibId == lib.id
                    Button { currentLibId = lib.id } label: {
                        HStack(spacing: 5) {
                            Image(systemName: lib.type == .webdav ? "network" : "externaldrive")
                                .font(.system(size: 11))
                            Text(lib.name).font(Typography.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(active ? Brand.accent : Brand.chipFill))
                        .foregroundStyle(active ? .white : Brand.label)
                        .overlay(Capsule().strokeBorder(active ? Color.clear : Brand.separator.opacity(0.6), lineWidth: 0.5))
                        .opacity(lib.enabled ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!lib.enabled)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: 路径导航条
    private var pathBar: some View {
        HStack(spacing: Spacing.xs) {
            Button { navigateUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentPath.isEmpty ? Brand.secondaryLabel.opacity(0.4) : Brand.label)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Brand.chipFill))
            }
            .buttonStyle(.plain)
            .disabled(currentPath.isEmpty)

            Text(currentPath.isEmpty ? "根目录" : currentPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Brand.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: 内容
    @ViewBuilder
    private var content: some View {
        if nm.libraries.isEmpty {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Brand.secondaryLabel)
                Text("尚未添加 NAS 资源库").font(Typography.body)
                Text("请到「设置 → 资源库」添加 WebDAV 或本机挂载目录")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.secondaryLabel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ErrorView(error, retry: { Task { await load() } })
        } else if items.isEmpty && isLoading {
            LoadingView("正在扫描媒体库…")
        } else if items.isEmpty {
            EmptyState("该目录暂无视频", systemImage: "film", description: "支持 mp4 / mkv / mov / m4v / avi / wmv / flv / ts / m3u8")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(items) { d in
                        NASCard(d)
                            .onTapGesture { onSelect(d) }
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    private func navigateUp() {
        guard !currentPath.isEmpty else { return }
        let parts = currentPath.split(separator: "/").map(String.init)
        currentPath = parts.dropLast().joined(separator: "/")
        Task { await load() }
    }

    private func load() async {
        guard let libId = currentLibId else { items = []; return }
        isLoading = true; error = nil
        do {
            items = try await nm.browse(id: libId, path: currentPath)
        } catch {
            self.error = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }
}

/// NAS 视频卡片（无封面，用文件名+图标占位）。
private struct NASCard: View {
    let drama: Drama
    init(_ d: Drama) { self.drama = d }

    private var isDir: Bool { drama.id.contains("|dir|") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.chipFill)
                    .aspectRatio(2/3, contentMode: .fit)
                Image(systemName: isDir ? "folder.fill" : "play.rectangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Brand.secondaryLabel.opacity(0.6))
                if let cnt = drama.episodeCount, cnt > 1 {
                    Text("\(cnt)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            Text(drama.title)
                .font(Typography.caption)
                .foregroundStyle(Brand.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let st = drama.updateStatus {
                Text(st)
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.secondaryLabel)
            }
        }
        .contentShape(Rectangle())
    }
}
