import SwiftUI
import HongguoGatewayCore

// MARK: - 弹幕渲染层（M4）
// 叠在视频层之上的 SwiftUI overlay：滚动弹幕横向平移、顶部/底部弹幕居中驻留。
// 用 TimelineView 驱动逐帧动画，跟随引擎 active 集合。

public struct DanmakuOverlay: View {
    @ObservedObject var engine: DanmakuEngine
    var fontScale: Double = 1.0
    var opacity: Double = 0.85
    /// 滚动弹幕占屏区域比例（顶部留白给顶/底弹幕）。
    var scrollAreaRatio: CGFloat = 0.5

    public init(engine: DanmakuEngine, fontScale: Double = 1.0, opacity: Double = 0.85) {
        self.engine = engine
        self.fontScale = fontScale
        self.opacity = opacity
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 滚动弹幕
                scrollLayer(size: geo.size)
                // 顶部弹幕
                pinnedLayer(mode: 1, size: geo.size)
                // 底部弹幕
                pinnedLayer(mode: 2, size: geo.size)
            }
            .clipped()
            .allowsHitTesting(false)   // 不拦截播放器手势
        }
    }

    // MARK: 滚动弹幕（从右往左）
    @ViewBuilder
    private func scrollLayer(size: CGSize) -> some View {
        let scroll = engine.active.filter { $0.mode == 0 }
        // 直接用播放时钟推进（引擎 currentPlayTime 随 tick 更新），暂停时弹幕自然定格。
        ZStack(alignment: .topLeading) {
            ForEach(scroll) { e in
                let progress = min(max((engine.currentPlayTime - e.time) / engine.scrollDuration, 0), 1)
                // 从屏幕右缘外 → 左缘外
                let travel = size.width + textWidth(e.text)
                let x = size.width - travel * progress
                Text(e.text)
                    .font(.system(size: 16 * fontScale, weight: .medium))
                    .foregroundStyle(color(for: e))
                    .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    .fixedSize()
                    .position(x: x, y: laneY(for: e, in: size.height * scrollAreaRatio))
                    .opacity(opacity)
            }
        }
    }

    // MARK: 顶部/底部驻留弹幕
    @ViewBuilder
    private func pinnedLayer(mode: Int, size: CGSize) -> some View {
        let items = engine.active.filter { $0.mode == mode }
        VStack(spacing: 2) {
            if mode == 2 { Spacer(minLength: 0) }
            ForEach(Array(items.suffix(6))) { e in   // 最多驻留 6 行
                Text(e.text)
                    .font(.system(size: 15 * fontScale, weight: .medium))
                    .foregroundStyle(color(for: e))
                    .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    .opacity(opacity)
            }
            if mode == 1 { Spacer(minLength: 0) }
        }
        .frame(width: size.width)
        .padding(mode == 1 ? .top : .bottom, 8)
    }

    // MARK: - 工具

    /// 车道 Y：按 id hash 分散到若干车道，避免滚动弹幕重叠。
    private func laneY(for e: DanmakuEntry, in areaHeight: CGFloat) -> CGFloat {
        let lanes = max(Int(areaHeight / 24), 1)
        let h = abs(e.id.hashValue)
        let lane = h % lanes
        return 14 + CGFloat(lane) * 24
    }

    private func textWidth(_ s: String) -> CGFloat {
        CGFloat(s.count) * 16 * fontScale
    }

    private func color(for e: DanmakuEntry) -> Color {
        guard let hex = e.color else { return .white }
        return Color(hex: hex) ?? .white
    }
}

// MARK: - Color hex 支持
private extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
