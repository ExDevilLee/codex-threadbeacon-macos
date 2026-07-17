import Combine
import Foundation

public struct ThreadLoadRequest: Equatable, Sendable {
    public let expandedThreadIDs: Set<String>
    public let includedThreadIDs: Set<String>
    public let favoriteThreadIDs: Set<String>
    public let recentLimit: Int

    public init(
        expandedThreadIDs: Set<String>,
        includedThreadIDs: Set<String>,
        favoriteThreadIDs: Set<String> = [],
        recentLimit: Int
    ) {
        self.expandedThreadIDs = expandedThreadIDs
        self.includedThreadIDs = includedThreadIDs
        self.favoriteThreadIDs = favoriteThreadIDs
        self.recentLimit = recentLimit
    }
}

@MainActor
public final class ThreadStatusStore: ObservableObject {
    @Published public private(set) var snapshots: [ThreadSnapshot] = []
    @Published public private(set) var ignoredSnapshots: [ThreadSnapshot] = []
    @Published public private(set) var lastRefreshedAt: Date?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var expandedThreadIDs: Set<String> = []

    public private(set) var preferences: ThreadListPreferences

    private let load: @Sendable (ThreadLoadRequest) async throws -> [ThreadSnapshot]
    private let now: @Sendable () -> Date
    private let visibleLimit: Int
    private var candidateSnapshots: [ThreadSnapshot] = []
    private var notificationTracker: SoundNotificationTracker
    private var pendingRefreshPolicy: RefreshNotificationPolicy?
    private let onNotification: @MainActor (SoundNotificationEvent) -> Void
    private let onNotificationHistoryChange: @MainActor ([String]) -> Void
    private let onPreferencesChange: @MainActor (ThreadListPreferences) -> Void

    public init(
        load: @escaping @Sendable (ThreadLoadRequest) async throws -> [ThreadSnapshot],
        now: @escaping @Sendable () -> Date = Date.init,
        initialPreferences: ThreadListPreferences = .empty,
        visibleLimit: Int = 8,
        notificationTracker: SoundNotificationTracker = SoundNotificationTracker(),
        onNotification: @escaping @MainActor (SoundNotificationEvent) -> Void = { _ in },
        onNotificationHistoryChange: @escaping @MainActor ([String]) -> Void = { _ in },
        onPreferencesChange: @escaping @MainActor (ThreadListPreferences) -> Void = { _ in }
    ) {
        self.load = load
        self.now = now
        self.preferences = initialPreferences
        self.visibleLimit = max(1, visibleLimit)
        self.notificationTracker = notificationTracker
        self.onNotification = onNotification
        self.onNotificationHistoryChange = onNotificationHistoryChange
        self.onPreferencesChange = onPreferencesChange
    }

    public var ignoredThreadIDs: [String] {
        preferences.ignoredRules.keys.sorted()
    }

    public func isPinned(_ threadID: String) -> Bool {
        preferences.pinnedThreadIDs.contains(threadID)
    }

    public func isFavorite(_ threadID: String) -> Bool {
        preferences.favoriteThreadIDs.contains(threadID)
    }

    public var showsFavoritesOnly: Bool {
        preferences.showsFavoritesOnly
    }

    public func ignoredTitle(for threadID: String) -> String? {
        candidateSnapshots.first { $0.id == threadID }?.title
    }

    public func toggleExpansion(for threadID: String) {
        if expandedThreadIDs.contains(threadID) {
            expandedThreadIDs.remove(threadID)
        } else {
            expandedThreadIDs.insert(threadID)
        }
    }

    public func togglePin(for threadID: String) {
        updatePreferences { preferences in
            if preferences.pinnedThreadIDs.contains(threadID) {
                preferences.pinnedThreadIDs.remove(threadID)
            } else {
                preferences.pinnedThreadIDs.insert(threadID)
            }
        }
    }

    public func toggleFavorite(for threadID: String) {
        updatePreferences { preferences in
            if preferences.favoriteThreadIDs.contains(threadID) {
                preferences.favoriteThreadIDs.remove(threadID)
            } else {
                preferences.favoriteThreadIDs.insert(threadID)
            }
        }
    }

    public func toggleFavoritesOnly() {
        updatePreferences { preferences in
            preferences.showsFavoritesOnly.toggle()
        }
    }

    public func ignore(_ threadID: String) {
        updatePreferences { preferences in
            preferences.pinnedThreadIDs.remove(threadID)
            preferences.ignoredRules[threadID] = IgnoredThreadRule(
                threadID: threadID,
                ignoredAt: now(),
                mode: .untilNextTurn
            )
        }
        expandedThreadIDs.remove(threadID)
    }

    public func restoreIgnored(_ threadID: String) {
        updatePreferences { preferences in
            preferences.ignoredRules.removeValue(forKey: threadID)
        }
    }

    public func restoreAllIgnored() {
        updatePreferences { preferences in
            preferences.ignoredRules.removeAll()
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
            let request = loadRequest()
            do {
                let nextSnapshots = try await Task.detached(priority: .utility) {
                    try await operation(request)
                }.value
                applyCandidates(nextSnapshots)
                lastRefreshedAt = now()
                errorMessage = nil

                let previousHistory = notificationTracker.seenEventIDs
                let events = notificationTracker.observe(snapshots, policy: currentPolicy)
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

    private func loadRequest() -> ThreadLoadRequest {
        let ignoredIDs = Set(preferences.ignoredRules.keys)
        let includedIDs = preferences.pinnedThreadIDs.union(ignoredIDs)
        let recentLimit = min(Int(Int32.max), visibleLimit + ignoredIDs.count)
        return ThreadLoadRequest(
            expandedThreadIDs: expandedThreadIDs,
            includedThreadIDs: includedIDs,
            favoriteThreadIDs: preferences.favoriteThreadIDs,
            recentLimit: recentLimit
        )
    }

    private func applyCandidates(_ candidates: [ThreadSnapshot]) {
        candidateSnapshots = candidates
        let previousPreferences = preferences
        preferences.pinnedThreadIDs.formIntersection(candidates.map(\.id))
        let result = ThreadListPolicy.evaluate(
            candidates: candidates,
            preferences: preferences,
            limit: visibleLimit
        )
        preferences = result.preferences
        snapshots = result.visibleSnapshots
        ignoredSnapshots = result.ignoredSnapshots
        if preferences != previousPreferences {
            onPreferencesChange(preferences)
        }
    }

    private func updatePreferences(
        _ update: (inout ThreadListPreferences) -> Void
    ) {
        let previousPreferences = preferences
        update(&preferences)
        let result = ThreadListPolicy.evaluate(
            candidates: candidateSnapshots,
            preferences: preferences,
            limit: visibleLimit
        )
        preferences = result.preferences
        snapshots = result.visibleSnapshots
        ignoredSnapshots = result.ignoredSnapshots
        if preferences != previousPreferences {
            onPreferencesChange(preferences)
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
