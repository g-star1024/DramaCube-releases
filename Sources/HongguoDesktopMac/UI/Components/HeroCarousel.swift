import SwiftUI
import HongguoCore

/// 首页 Hero 轮播：大图 + 标题渐变遮罩 + 自动轮换 + 指示点 + 左右切换。
/// 悬停时暂停自动轮换，点击任意处打开详情。
public struct HeroCarousel: View {
    let items: [Drama]
    let onSelect: (Drama) -> Void

    @State private var index: Int = 0
    @State private var isHovering = false
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    public init(items: [Drama], onSelect: @escaping (Drama) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    private var current: Drama? {
        items.indices.contains(index) ? items[index] : items.first
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 关键：给图片一个确定高度的 frame 并裁切。
            // CoverImage 内部 scaledToFill 无约束会把 ZStack 撑到数千 pt 高，
            // bottomLeading 对齐的标题会被排到可视区外（标题"消失"的根因）。
            bannerImage
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()
                .id(index)
                .transition(.opacity)

            LinearGradient(
                colors: [.clear, .black.opacity(0.30), .black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            if let drama = current {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Label("正在热播", systemImage: "flame.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Brand.accent))
                        if let cnt = drama.episodeCount {
                            Text("\(cnt) 集")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.white.opacity(0.18)))
                        }
                    }
                    // 剧名：左下角大字 + 阴影，保证任何封面上都清晰可读
                    Text(drama.title)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.65), radius: 5, y: 2)
                    if let desc = drama.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                            .frame(maxWidth: 560, alignment: .leading)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    }
                    HStack(spacing: Spacing.sm) {
                        Label("立即观看", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Brand.accent))
                    }
                    .padding(.top, 2)
                }
                .padding(Spacing.xl)
            }
        }
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .bottomTrailing) { dots.padding(Spacing.lg) }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.separator.opacity(0.4), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg))
        .onTapGesture {
            if let drama = current { onSelect(drama) }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onReceive(timer) { _ in
            guard !isHovering, items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) { advance() }
        }
        .overlay(alignment: .leading) { chevron(forward: false) }
        .overlay(alignment: .trailing) { chevron(forward: true) }
        .animation(.easeInOut(duration: 0.45), value: index)
    }

    @ViewBuilder
    private var bannerImage: some View {
        if let drama = current, let urlStr = drama.coverURL, let url = URL(string: urlStr) {
            CoverImage(url)
        } else {
            heroPlaceholder
        }
    }

    private var heroPlaceholder: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.accent.opacity(0.6), .orange.opacity(0.45)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// 左右切换按钮：44pt 大热区 + 半透明底，未悬停时也保持可见（更易点中）。
    private func chevron(forward: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) { advance(by: forward ? 1 : -1) }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(0.40)))
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1.0 : 0.65)
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .padding(.horizontal, Spacing.lg)
        .disabled(items.count < 2)
        .help(forward ? "下一张" : "上一张")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.white.opacity(0.45))
                    .frame(width: i == index ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
    }

    private func advance(by delta: Int = 1) {
        guard !items.isEmpty else { return }
        index = (index + delta + items.count) % items.count
    }
}
