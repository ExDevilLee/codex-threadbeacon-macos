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
    @Published public private(set) var dataSourceHealth: DataSourceHealthReport?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var expandedThreadIDs: Set<String> = []
    @Published public private(set) var restoringThreadIDs: Set<String> = []
    @Published public private(set) var archiveRestoreFeedback: ArchiveRestoreFeedback?

    public private(set) var preferences: ThreadListPreferences

    private let loadResult: @Sendable (ThreadLoadRequest) async throws -> ThreadStatusLoadResult
    private let restoreArchive: @Sendable (String) async throws -> Void
    private let now: @Sendable () -> Date
    private var visibleLimit: Int
    private var candidateSnapshots: [ThreadSnapshot] = []
    private var notificationTracker: SoundNotificationTracker
    private var autoRecoveryEpisodeIDs: Set<String> = []
    private var pendingRefreshPolicy: RefreshNotificationPolicy?
    private let onNotification: @MainActor (SoundNotificationEvent) -> Void
    private let onAutoRecovery: @MainActor (AutoRecoveryCandidate) -> Void
    private let onNotificationHistoryChange: @MainActor ([String]) -> Void
    private let onPreferencesChange: @MainActor (ThreadListPreferences) -> Void

    public convenience init(
        load: @escaping @Sendable (ThreadLoadRequest) async throws -> [ThreadSnapshot],
        restoreArchive: @escaping @Sendable (String) async throws -> Void = { _ in
            throw ArchiveRestoreError.cliNotFound
        },
        now: @escaping @Sendable () -> Date = Date.init,
        initialPreferences: ThreadListPreferences = .empty,
        visibleLimit: Int = 8,
        notificationTracker: SoundNotificationTracker = SoundNotificationTracker(),
        onNotification: @escaping @MainActor (SoundNotificationEvent) -> Void = { _ in },
        onAutoRecovery: @escaping @MainActor (AutoRecoveryCandidate) -> Void = { _ in },
        onNotificationHistoryChange: @escaping @MainActor ([String]) -> Void = { _ in },
        onPreferencesChange: @escaping @MainActor (ThreadListPreferences) -> Void = { _ in }
    ) {
        self.init(
            loadResult: { request in
                ThreadStatusLoadResult(
                    snapshots: try await load(request),
                    health: DataSourceHealthReport(
                        taskDatabase: .healthy,
                        renameIndex: .notUsed,
                        rollout: .notUsed,
                        serviceLogs: .notUsed,
                        rolloutSuccessCount: 0,
                        rolloutFailureCount: 0,
                        lastSuccessfulRefreshAt: nil
                    )
                )
            },
            restoreArchive: restoreArchive,
            now: now,
            initialPreferences: initialPreferences,
            visibleLimit: visibleLimit,
            notificationTracker: notificationTracker,
            onNotification: onNotification,
            onAutoRecovery: onAutoRecovery,
            onNotificationHistoryChange: onNotificationHistoryChange,
            onPreferencesChange: onPreferencesChange
        )
    }

    public init(
        loadResult: @escaping @Sendable (ThreadLoadRequest) async throws -> ThreadStatusLoadResult,
        restoreArchive: @escaping @Sendable (String) async throws -> Void = { _ in
            throw ArchiveRestoreError.cliNotFound
        },
        now: @escaping @Sendable () -> Date = Date.init,
        initialPreferences: ThreadListPreferences = .empty,
        visibleLimit: Int = 8,
        notificationTracker: SoundNotificationTracker = SoundNotificationTracker(),
        onNotification: @escaping @MainActor (SoundNotificationEvent) -> Void = { _ in },
        onAutoRecovery: @escaping @MainActor (AutoRecoveryCandidate) -> Void = { _ in },
        onNotificationHistoryChange: @escaping @MainActor ([String]) -> Void = { _ in },
        onPreferencesChange: @escaping @MainActor (ThreadListPreferences) -> Void = { _ in }
    ) {
        self.loadResult = loadResult
        self.restoreArchive = restoreArchive
        self.now = now
        self.preferences = initialPreferences
        self.visibleLimit = max(1, visibleLimit)
        self.notificationTracker = notificationTracker
        self.onNotification = onNotification
        self.onAutoRecovery = onAutoRecovery
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

    public func isRestoringArchive(_ threadID: String) -> Bool {
        restoringThreadIDs.contains(threadID)
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

    public func updateVisibleLimit(_ limit: Int) {
        let nextLimit = max(1, limit)
        guard nextLimit != visibleLimit else { return }
        visibleLimit = nextLimit
        applyCurrentPreferences()
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

    public func restoreArchivedFavorite(_ threadID: String) async {
        guard !restoringThreadIDs.contains(threadID),
              preferences.favoriteThreadIDs.contains(threadID),
              candidateSnapshots.first(where: { $0.id == threadID })?.isArchived == true else {
            return
        }

        restoringThreadIDs.insert(threadID)
        archiveRestoreFeedback = nil
        defer { restoringThreadIDs.remove(threadID) }

        do {
            try await restoreArchive(threadID)
            archiveRestoreFeedback = .success(threadID: threadID)
            await refresh(notificationPolicy: .baseline)
        } catch {
            archiveRestoreFeedback = .failure(
                threadID: threadID,
                message: error.localizedDescription
            )
        }
    }

    public func dismissArchiveRestoreFeedback() {
        archiveRestoreFeedback = nil
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
            let operation = loadResult
            let request = loadRequest()
            do {
                let nextResult = try await Task.detached(priority: .utility) {
                    try await operation(request)
                }.value
                let refreshedAt = now()
                applyCandidates(nextResult.snapshots)
                lastRefreshedAt = refreshedAt
                dataSourceHealth = nextResult.health.recordingSuccessfulRefresh(at: refreshedAt)
                errorMessage = nil

                let previousHistory = notificationTracker.seenEventIDs
                let events = notificationTracker.observe(snapshots, policy: currentPolicy)
                if notificationTracker.seenEventIDs != previousHistory {
                    onNotificationHistoryChange(notificationTracker.seenEventIDs)
                }
                events.forEach(onNotification)
                observeAutoRecovery(policy: currentPolicy)
            } catch let error as ThreadStatusLoadFailure {
                if let lastRefreshedAt {
                    dataSourceHealth = error.health.recordingSuccessfulRefresh(at: lastRefreshedAt)
                } else {
                    dataSourceHealth = error.health
                }
                errorMessage = error.localizedDescription
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
        applyCurrentPreferences(previousPreferences: previousPreferences)
    }

    private func applyCurrentPreferences(previousPreferences: ThreadListPreferences? = nil) {
        let previousPreferences = previousPreferences ?? preferences
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

    private func observeAutoRecovery(policy: RefreshNotificationPolicy) {
        for snapshot in snapshots {
            guard let incident = snapshot.serviceIncident,
                  incident.phase == .failed else {
                continue
            }
            let isNew = autoRecoveryEpisodeIDs.insert("\(snapshot.id):\(incident.episodeID)").inserted
            guard isNew, policy == .notify else { continue }
            onAutoRecovery(AutoRecoveryCandidate(
                threadID: snapshot.id,
                episodeID: incident.episodeID,
                incidentType: AutoRecoveryIncidentType(incidentKind: incident.kind),
                incidentLabel: incident.logLabel
            ))
        }
    }
}

private extension ServiceIncident {
    var logLabel: String {
        switch kind {
        case .badRequest: "HTTP 400"
        case .httpRateLimit: "HTTP 429"
        case .serviceUnavailable: "HTTP 503"
        case let .httpStatus(code): "HTTP \(code)"
        case .modelCapacity: "模型容量"
        }
    }
}
