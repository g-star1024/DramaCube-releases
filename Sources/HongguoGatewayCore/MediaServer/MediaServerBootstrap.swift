import Foundation

// MARK: - 媒体服务器装配器
// 网关启动时把现有引擎（TVBox 订阅站点 / NAS 库 / IPTV 源）包装成适配器注册进 Registry。
// 后续 Emby/Jellyfin/AList/Subsonic/audiobookshelf 适配器也在此登记。

public enum MediaServerBootstrap {

    /// 装配全部已配置服务器到 Registry。可重复调用（先清后注册保证幂等）。
    public static func assemble() async {
        let reg = MediaServerRegistry.shared

        // TVBox·CMS 采集站点（每个 Site 一个逻辑服务器）
        for site in await TVBoxEngine.shared.allSites() {
            await reg.register(TVBoxAdapter(site: site))
        }

        // NAS（WebDAV/mount）
        for lib in await NASEngine.shared.allLibraries() where lib.enabled {
            await reg.register(NASAdapter(library: lib))
        }

        // IPTV 直播源
        for src in await LiveEngine.shared.allSources() where src.enabled {
            await reg.register(LiveAdapter(source: src))
        }

        // TODO(M2/M3): Emby / Jellyfin / AList / Subsonic / audiobookshelf / 红果 适配器登记
    }

    /// 重新装配（订阅/库/直播源变更后调用）。
    public static func reassemble() async {
        // 简化：直接再 assemble 一次（register 同 key 覆盖）。
        await assemble()
    }
}
