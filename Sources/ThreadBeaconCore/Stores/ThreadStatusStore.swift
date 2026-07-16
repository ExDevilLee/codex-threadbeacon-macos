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
    private var notificationTracker: SoundNotificationTracker
    private let onNotification: @MainActor (SoundNotificationEvent) -> Void
    private let onNotificationHistoryChange: @MainActor ([String]) -> Void

    public init(
        load: @escaping @Sendable () async throws -> [ThreadSnapshot],
        now: @escaping @Sendable () -> Date = Date.init,
        notificationTracker: SoundNotificationTracker = SoundNotificationTracker(),
        onNotification: @escaping @MainActor (SoundNotificationEvent) -> Void = { _ in },
        onNotificationHistoryChange: @escaping @MainActor ([String]) -> Void = { _ in }
    ) {
        self.load = load
        self.now = now
        self.notificationTracker = notificationTracker
        self.onNotification = onNotification
        self.onNotificationHistoryChange = onNotificationHistoryChange
    }

    public func refresh(notificationPolicy: RefreshNotificationPolicy = .baseline) async {
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

            let previousHistory = notificationTracker.seenEventIDs
            let events = notificationTracker.observe(nextSnapshots, policy: notificationPolicy)
            if notificationTracker.seenEventIDs != previousHistory {
                onNotificationHistoryChange(notificationTracker.seenEventIDs)
            }
            events.forEach(onNotification)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
