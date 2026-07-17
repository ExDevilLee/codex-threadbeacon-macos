import Combine
import Foundation

@MainActor
public final class ThreadStatusStore: ObservableObject {
    @Published public private(set) var snapshots: [ThreadSnapshot] = []
    @Published public private(set) var lastRefreshedAt: Date?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var expandedThreadIDs: Set<String> = []

    private let load: @Sendable (Set<String>) async throws -> [ThreadSnapshot]
    private let now: @Sendable () -> Date
    private var notificationTracker: SoundNotificationTracker
    private var pendingRefreshPolicy: RefreshNotificationPolicy?
    private let onNotification: @MainActor (SoundNotificationEvent) -> Void
    private let onNotificationHistoryChange: @MainActor ([String]) -> Void

    public init(
        load: @escaping @Sendable (Set<String>) async throws -> [ThreadSnapshot],
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

    public func toggleExpansion(for threadID: String) {
        if expandedThreadIDs.contains(threadID) {
            expandedThreadIDs.remove(threadID)
        } else {
            expandedThreadIDs.insert(threadID)
        }
    }

    public func refresh(notificationPolicy: RefreshNotificationPolicy = .baseline) async {
        if isRefreshing {
            pendingRefreshPolicy = mergedPolicy(pendingRefreshPolicy, notificationPolicy)
            return
        }
        isRefreshing = true
        var currentPolicy = notificationPolicy

        while true {
            let operation = load
            let requestedExpandedThreadIDs = expandedThreadIDs
            do {
                let nextSnapshots = try await Task.detached(priority: .utility) {
                    try await operation(requestedExpandedThreadIDs)
                }.value
                snapshots = nextSnapshots
                lastRefreshedAt = now()
                errorMessage = nil

                let previousHistory = notificationTracker.seenEventIDs
                let events = notificationTracker.observe(nextSnapshots, policy: currentPolicy)
                if notificationTracker.seenEventIDs != previousHistory {
                    onNotificationHistoryChange(notificationTracker.seenEventIDs)
                }
                events.forEach(onNotification)
            } catch {
                errorMessage = error.localizedDescription
            }

            guard let nextPolicy = pendingRefreshPolicy else {
                isRefreshing = false
                return
            }
            pendingRefreshPolicy = nil
            currentPolicy = nextPolicy
        }
    }

    private func mergedPolicy(
        _ existing: RefreshNotificationPolicy?,
        _ incoming: RefreshNotificationPolicy
    ) -> RefreshNotificationPolicy {
        if existing == .notify || incoming == .notify {
            return .notify
        }
        return .baseline
    }
}
