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
    public static let shared: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.connectionProxyDictionary = [:]
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
}
