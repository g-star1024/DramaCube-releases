import Foundation
import SwiftData

/// SwiftData 持久化容器单例。
///
/// App 启动时通过 `.modelContainer(PersistenceController.shared.container)` 注入；
/// Repository 直接使用其 `mainContext` 做 CRUD。
@MainActor
public final class PersistenceController {
    public static let shared = PersistenceController()

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    private init() {
        let schema = Schema([FavoriteItem.self, HistoryItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.container = try! ModelContainer(for: schema, configurations: [config])
    }
}
