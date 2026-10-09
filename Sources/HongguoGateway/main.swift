import Foundation
import HongguoCore
import HongguoGatewayCore

/// 独立运行的网关可执行文件（调试 / 单独部署用）。
/// 正常发布形态下，网关由 App 进程内 `GatewayController` 启动，无需此入口。
@main
struct Gateway {
    static func main() async throws {
        try await GatewayServer.run(port: AppConfig.gatewayPort)
    }
}
