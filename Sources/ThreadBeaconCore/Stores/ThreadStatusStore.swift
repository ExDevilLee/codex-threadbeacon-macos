import Combine
import Foundation

@MainActor
public final class ThreadStatusStore: ObservableObject {
    @Published public private(set) var snapshots: [ThreadSnapshot] = []
    @Published public private(set) var lastRefreshedAt: Date?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isRefreshing = false

    private let load: @Sendable () async throws -> [ThreadSnapshot]
    private let now: @Sendable () -> Date

    public init(
        load: @escaping @Sendable () async throws -> [ThreadSnapshot],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.load = load
        self.now = now
    }

    public func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let operation = load
        do {
            let nextSnapshots = try await Task.detached(priority: .utility) {
                try await operation()
            }.value
            snapshots = nextSnapshots
            lastRefreshedAt = now()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
