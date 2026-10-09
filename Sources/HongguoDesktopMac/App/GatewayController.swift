import Foundation
import HongguoGatewayCore

/// 网关生命周期控制器（App 进程内接管）。
///
/// App 启动时调用 `start()`，在后台 Task 中运行 Hummingbird；
/// App 退出时 macOS 自动回收进程，网关随之关闭，无残留监听。
@MainActor
public final class GatewayController: ObservableObject {
    public static let shared = GatewayController()

    private var runTask: Task<Void, Never>?

    @Published public private(set) var isRunning = false

    private init() {}

    /// 启动本地网关（幂等：已运行则忽略）。
    public func start() {
        guard runTask == nil else { return }
        let port = AppSettings.shared.gatewayPort
        runTask = Task { [weak self] in
            await MainActor.run { self?.isRunning = true }
            // app.run() 阻塞，直到进程退出或 Task 取消。
            try? await GatewayServer.run(port: port)
            await MainActor.run { self?.isRunning = false }
        }
    }

    /// 停止网关（通常无需手动调用，App 退出即回收）。
    public func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }
}
