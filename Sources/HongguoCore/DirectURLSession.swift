import Foundation

/// 强制直连（绕开系统代理）的 URLSession。
///
/// 背景（v1.2.2 修复）：用户机器常开全局代理 / VPN（Clash 等），系统代理把出口切到境外。
/// 而采集站 / 直播 / 红果的 CDN 全部锁中国大陆 IP，对境外出口返回「请使用国内网络访问」403。
/// URLSession 默认遵循系统代理 → 走境外 → 全部 403（现象：curl 直连 200、App 播放全挂）。
///
/// 解决：媒体拉流与源站 API 请求统一走本 session（`connectionProxyDictionary = [:]` 清空代理），
/// 强制直连国内出口。豆瓣等本就允许直连的域名不受影响。
public enum DirectURLSession {
    /// 清空代理配置的直连 session（国内 CDN 拉流专用）。
    /// 用 ephemeral（不写盘缓存/cookie，避免与默认配置的代理行为耦合），并显式置空代理字典。
    public static let shared: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        // 显式禁用一切系统代理（HTTP/HTTPS/SOCKS），强制直连国内出口。
        // 只设空字典在 .default 上不彻底：.default 会合并系统 scutil 代理，ephemeral + 置空才确保直连。
        cfg.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
        ] as [String: Any]
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        // 每主机默认 6 连接上限会级联限流：封面并发提到 12 后这里同步放到 16，
        // 否则第 7 张起的封面仍压在 session 层排队（TVBox 首页封面出图慢的叠加根因）。
        // 仅放宽许可、不强制多用，视频拉流仍按需单连接，不影响既有行为。
        cfg.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: cfg)
    }()
}
