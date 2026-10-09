import SwiftUI

/// 设计系统 —— 红果品牌与 macOS HIG 对齐的视觉令牌。
public enum Brand {
    /// 主品牌色（红果粉 #FF2D55）。
    public static let pink = Color(red: 1.0, green: 0.176, blue: 0.333)
    /// 深色模式下更亮的粉。
    public static let pinkDark = Color(red: 1.0, green: 0.36, blue: 0.53)
    public static let background = Color(nsColor: .windowBackgroundColor)
    public static let secondaryBackground = Color(nsColor: .underPageBackgroundColor)
    public static let separator = Color(nsColor: .separatorColor)
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
