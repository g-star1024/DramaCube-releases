// App 可执行入口（SPM target）。
//
// HongguoApp 作为库类型不带 @main；此处以单行入口引用其 App 实现，
// SwiftUI 的 App.main() 默认实现会实例化 HongguoApp 并启动 NSApplication 事件循环。
// 该二进制由 Scripts/build-app-bundle.sh 装入 .app 包（需 Info.plist 才能正常启动 GUI）。

import SwiftUI
import HongguoDesktopMac

@main
struct Main {
    static func main() {
        // 无头自测：HongguoMacApp --mpv-probe <url>
        // 直接用链进 app 的 libmpv 无头拉流读元数据，验证 mpv 内核真实可用（不走 GUI）。
        let args = CommandLine.arguments
        if args.count >= 3, args[1] == "--mpv-probe" {
            MpvProbe.run(url: args[2])
            return
        }
        HongguoApp.main()
    }
}
