import Foundation
import LibMPV

/// mpv 内核无头自测（`HongguoMacApp --mpv-probe <url>`）。
/// 直接调链进 app 的 libmpv C API：无头（vo/ao=null）拉流读 duration/视频轨，
/// 验证 mpv 内核对网关代理 m3u8 / 直链的真实解码能力，不走 GUI / Metal 渲染。
public enum MpvProbe {
    public static func run(url: String) {
        guard let mpv = mpv_create() else { print("FAIL mpv_create"); exit(1) }
        mpv_set_property_string(mpv, "vo", "null")
        mpv_set_property_string(mpv, "ao", "null")
        mpv_set_property_string(mpv, "hwdec", "no")
        mpv_set_property_string(mpv, "cache", "yes")
        mpv_request_log_messages(mpv, "warn")
        guard mpv_initialize(mpv) >= 0 else { print("FAIL mpv_initialize"); exit(1) }
        print("OK mpv_initialize")
        let cmd: [String] = ["loadfile", url, "replace"]
        var cargs: [UnsafePointer<CChar>?] = cmd.map { UnsafePointer(strdup($0)) } + [nil]
        mpv_command(mpv, &cargs)

        var gotMeta = false
        for _ in 0..<300 {  // 最多 30s
            guard let ev = mpv_wait_event(mpv, 0.1) else { continue }
            let id = ev.pointee.event_id
            if id == MPV_EVENT_FILE_LOADED {
                print("OK FILE_LOADED")
                var dur = 0.0
                if mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur) >= 0, dur > 0 {
                    print("OK duration=\(dur)s"); gotMeta = true
                }
                var w: Int64 = 0, h: Int64 = 0
                mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &w)
                mpv_get_property(mpv, "video-params/h", MPV_FORMAT_INT64, &h)
                if w > 0 { print("OK video=\(w)x\(h)"); gotMeta = true }
                var codec: UnsafeMutablePointer<CChar>?
                if mpv_get_property(mpv, "video-codec", MPV_FORMAT_STRING, &codec) >= 0, let c = codec {
                    print("OK codec=\(String(cString: c))"); mpv_free(c)
                }
                break
            }
            if id == MPV_EVENT_END_FILE {
                if let data = ev.pointee.data {
                    let ef = data.load(as: mpv_event_end_file.self)
                    print("END_FILE reason=\(ef.reason) error=\(ef.error)")
                }
                break
            }
            if id == MPV_EVENT_LOG_MESSAGE {
                if let data = ev.pointee.data {
                    let lm = data.load(as: mpv_event_log_message.self)
                    if let t = lm.text { fputs("[mpv] \(String(cString: t))", stderr) }
                }
            }
        }
        mpv_terminate_destroy(mpv)
        print(gotMeta ? "PROBE_OK" : "PROBE_FAIL")
        exit(gotMeta ? 0 : 1)
    }
}
