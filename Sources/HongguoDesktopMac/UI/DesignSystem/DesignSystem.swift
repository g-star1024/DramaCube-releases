import SwiftUI

/// 设计系统 —— 剧立方品牌与 macOS HIG 对齐的视觉令牌。
///
/// 2026-10 视觉升级：由系统灰切换为「暖阳奶油」色系，
/// 深色外观下自动回落到对应的暗色调（保持系统外观自适应）。
public enum Brand {
    /// 主品牌色（红果粉 #FF2D55）。
    public static let pink = Color(red: 1.0, green: 0.176, blue: 0.333)
    /// 深色模式下更亮的粉。
    public static let pinkDark = Color(red: 1.0, green: 0.36, blue: 0.53)
    /// 品牌强调色：自动随系统外观切换（浅色/深色）。
    public static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.0, green: 0.36, blue: 0.53, alpha: 1)
            : NSColor(red: 1.0, green: 0.176, blue: 0.333, alpha: 1)
    })

    // MARK: 暖阳色板（浅色 / 深色自适应）

    private static func warm(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    /// 窗口底色：暖米白（深色：暖炭黑）。
    public static let background = warm(light: (0.992, 0.984, 0.965), dark: (0.11, 0.10, 0.09))
    /// 次级面板底：奶油色（深色：略亮暖黑）。
    public static let secondaryBackground = warm(light: (0.965, 0.941, 0.898), dark: (0.16, 0.145, 0.13))
    /// 图片加载占位 / 失败底色：暖沙色（不再是灰）。
    public static let placeholder = warm(light: (0.949, 0.914, 0.855), dark: (0.22, 0.20, 0.18))
    /// 胶囊 / 卡片填充：近白暖色（在米白底上有轻微层次）。
    public static let chipFill = warm(light: (1.0, 0.996, 0.988), dark: (0.24, 0.22, 0.20))
    /// 分隔线：暖褐。
    public static let separator = warm(light: (0.89, 0.855, 0.80), dark: (0.28, 0.26, 0.24))

    public static let label = Color(nsColor: .labelColor)
    public static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
}

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 32
}

public enum Radius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 16
}

public enum Typography {
    public static let title = Font.title.bold()
    public static let headline = Font.headline
    public static let body = Font.body
    public static let caption = Font.caption
}

/// 通用卡片容器，统一圆角/背景/描边。
public struct Card<Content: View>: View {
    let content: Content
    public init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(Spacing.md)
            .background(Brand.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
