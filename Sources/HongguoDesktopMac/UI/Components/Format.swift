import Foundation

/// 通用格式化辅助。
public enum HongguoFormat {
    /// 秒 -> "mm:ss" / "h:mm:ss"。
    public static func duration(_ seconds: Double) -> String {
        guard seconds > 0, seconds.isFinite else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// 相对时间：刚刚 / x分钟前 / x小时前 / MM-dd。
    public static func relative(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        if diff < 86400 * 30 { return "\(Int(diff / 86400)) 天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
