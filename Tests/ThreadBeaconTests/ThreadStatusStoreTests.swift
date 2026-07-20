import ThreadBeaconCore
import Foundation

let threadStatusStoreTests = [
    TestCase(name: "store applies a new visible limit immediately and to the next load") {
        let requests = LoadRequestBox()
        let candidates = Array(1...6).map { index in
            storeListSnapshot(id: "task-\(index)", status: .idle, eventSecond: Double(index))
        }
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { request in
                    requests.append(request)
                    return candidates
                },
                visibleLimit: 4
            )
        }

        await store.refresh()
        await MainActor.run { store.updateVisibleLimit(6) }
        let expandedCount = await MainActor.run { store.snapshots.count }
        await store.refresh()

        try expect(expandedCount == 6, "changing the limit should immediately re-evaluate loaded tasks")
        try expect(requests.values.last?.recentLimit == 6, "the next refresh should request the new limit")
    },
    TestCase(name: "store refresh publishes snapshots and timestamp") {
        let snapshot = ThreadSnapshot(
            id: "running",
            title: "Running",
            status: .running,
            statusChangedAt: Date(),
            updatedAt: Date(),
            latestEventAt: Date()
        )
        let store = await MainActor.run {
            ThreadStatusStore(load: { _ in [snapshot] })
        }

        await store.refresh()
        let result = await MainActor.run {
            (store.snapshots, store.lastRefreshedAt, store.errorMessage)
        }

        try expect(result.0.map(\.status) == [.running], "refresh should publish loaded snapshots")
        try expect(result.1 != nil, "refresh should publish timestamp")
        try expect(result.2 == nil, "successful refresh should clear error")
    },
    TestCase(name: "store publishes health and preserves snapshots after a core failure") {
        let refreshedAt = Date(timeIntervalSince1970: 100)
        let snapshot = storeListSnapshot(id: "visible", status: .idle, eventSecond: 90)
        let healthy = storeHealthReport(taskDatabase: .healthy)
        let unavailable = storeHealthReport(
            taskDatabase: .unavailable("任务数据库不可用"),
            renameIndex: .notUsed,
            rollout: .notUsed,
            serviceLogs: .notUsed
        )
        let sequence = HealthLoadSequence(
            success: ThreadStatusLoadResult(snapshots: [snapshot], health: healthy),
            failure: ThreadStatusLoadFailure(health: unavailable)
        )
        let store = await MainActor.run {
            ThreadStatusStore(
                loadResult: { _ in try await sequence.next() },
                now: { refreshedAt }
            )
        }

        await store.refresh()
        let afterSuccess = await MainActor.run {
            (store.snapshots, store.dataSourceHealth, store.lastRefreshedAt)
        }
        await store.refresh()
        let afterFailure = await MainActor.run {
            (store.snapshots, store.dataSourceHealth, store.lastRefreshedAt, store.errorMessage)
        }

        try expect(afterSuccess.0.map(\.id) == ["visible"], "successful refresh should publish snapshots")
        try expect(afterSuccess.1?.overallStatus == .healthy, "successful refresh should publish health")
        try expect(afterSuccess.1?.lastSuccessfulRefreshAt == refreshedAt, "health should record success time")
        try expect(afterFailure.0.map(\.id) == ["visible"], "core failure should preserve prior snapshots")
        try expect(afterFailure.1?.overallStatus == .unavailable, "core failure should publish health")
        try expect(
            afterFailure.1?.lastSuccessfulRefreshAt == refreshedAt,
            "failed refresh should retain the last successful time"
        )
        try expect(afterFailure.2 == refreshedAt, "store should retain its last successful timestamp")
        try expect(afterFailure.3 == "Codex 任务数据库不可用", "store should publish sanitized error")
    },
    TestCase(name: "store emits only new automatic completion") {
        let first = completedStoreSnapshot(id: "thread-a", second: 10)
        let second = completedStoreSnapshot(id: "thread-a", second: 20)
        let sequence = SnapshotSequence(values: [[first], [second], [second]])
        let receivedEvents = EventBox()
        let receivedHistory = EventHistoryBox()
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in await sequence.next() },
                onNotification: { event in receivedEvents.append(event) },
                onNotificationHistoryChange: { ids in receivedHistory.replace(ids) }
            )
        }

        await store.refresh(notificationPolicy: .baseline)
        await store.refresh(notificationPolicy: .notify)
        await store.refresh(notificationPolicy: .notify)

        try expect(receivedEvents.values.count == 1, "only the new automatic completion should notify")
        try expect(receivedEvents.values.first?.category == .done, "completion should use done category")
        try expect(receivedHistory.values.count == 2, "new event IDs should be persisted")
    },
    TestCase(name: "store sends one recovery prompt for a new HTTP 400 incident") {
        let incident = ServiceIncident(
            episodeID: "turn-400",
            phase: .failed,
            kind: .badRequest,
            httpStatusCode: 400,
            retryAttempt: nil,
            retryLimit: nil,
            occurredAt: Date(timeIntervalSince1970: 10)
        )
        let snapshot = ThreadSnapshot(
            id: "thread-400",
            title: "thread-400",
            status: .error,
            statusChangedAt: incident.occurredAt,
            updatedAt: incident.occurredAt,
            latestEventAt: incident.occurredAt,
            serviceIncident: incident
        )
        let sequence = SnapshotSequence(values: [[], [snapshot], [snapshot]])
        let recoveryCalls = RecoveryCallBox()
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in await sequence.next() },
                onAutoRecovery: { threadID, _, _, prompt in
                    recoveryCalls.append(threadID: threadID, prompt: prompt)
                }
            )
        }

        await store.refresh(notificationPolicy: .baseline)
        await store.refresh(notificationPolicy: .notify)
        await store.refresh(notificationPolicy: .notify)

        try expect(recoveryCalls.values.count == 1, "one incident episode should trigger one prompt")
        try expect(recoveryCalls.values.first?.threadID == "thread-400", "prompt should target the failed thread")
        try expect(
            recoveryCalls.values.first?.prompt == "刚才中断了，请继续未完成的任务",
            "prompt should use the fixed recovery text"
        )
    },
    TestCase(name: "store recovers terminal 429 and skips 503") {
        let retryIncident = ServiceIncident(
            episodeID: "turn-429",
            phase: .failed,
            kind: .httpRateLimit,
            httpStatusCode: 429,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: Date(timeIntervalSince1970: 20)
        )
        let unavailableIncident = ServiceIncident(
            episodeID: "turn-503",
            phase: .failed,
            kind: .serviceUnavailable,
            httpStatusCode: 503,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: Date(timeIntervalSince1970: 20)
        )
        let snapshots = [retryIncident, unavailableIncident].enumerated().map { index, incident in
            ThreadSnapshot(
                id: "thread-\(index)",
                title: "thread-\(index)",
                status: .error,
                statusChangedAt: incident.occurredAt,
                updatedAt: incident.occurredAt,
                latestEventAt: incident.occurredAt,
                serviceIncident: incident
            )
        }
        let sequence = SnapshotSequence(values: [[], snapshots])
        let recoveryCalls = RecoveryCallBox()
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in await sequence.next() },
                onAutoRecovery: { threadID, _, _, prompt in
                    recoveryCalls.append(threadID: threadID, prompt: prompt)
                }
            )
        }

        await store.refresh(notificationPolicy: .baseline)
        await store.refresh(notificationPolicy: .notify)

        try expect(recoveryCalls.values.map(\.threadID) == ["thread-0"], "429 should recover while 503 stays excluded")
    },
    TestCase(name: "store passes transient expanded thread IDs to refreshes") {
        let receivedExpansions = ExpansionHistoryBox()
        let store = await MainActor.run {
            ThreadStatusStore(load: { request in
                receivedExpansions.append(request.expandedThreadIDs)
                return []
            })
        }

        await MainActor.run { store.toggleExpansion(for: "parent") }
        await store.refresh()
        let expanded = await MainActor.run { store.expandedThreadIDs }

        try expect(expanded == ["parent"], "expanded thread state should be retained in memory")
        try expect(receivedExpansions.values == [["parent"]], "refresh should request expanded children")

        await MainActor.run { store.toggleExpansion(for: "parent") }
        await store.refresh()
        let collapsed = await MainActor.run { store.expandedThreadIDs }

        try expect(collapsed.isEmpty, "second toggle should collapse the thread")
        try expect(receivedExpansions.values.last == [], "collapsed refresh should stop requesting children")
    },
    TestCase(name: "store queues expansion refresh while another refresh is running") {
        let gate = RefreshLoadGate()
        let store = await MainActor.run {
            ThreadStatusStore(load: { request in
                await gate.load(request.expandedThreadIDs)
            })
        }

        let initialRefresh = Task { await store.refresh() }
        await gate.waitUntilFirstLoadStarts()
        await MainActor.run { store.toggleExpansion(for: "parent") }
        await store.refresh()
        await gate.releaseFirstLoad()
        await initialRefresh.value

        let requests = await gate.requests
        try expect(
            requests == [[], ["parent"]],
            "an expansion during refresh should trigger one follow-up load"
        )
    },
    TestCase(name: "store requests list preference tasks with extra recent candidates") {
        let requests = LoadRequestBox()
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: ["pinned"],
            favoriteThreadIDs: ["favorite"],
            ignoredRules: [
                "ignored": IgnoredThreadRule(
                    threadID: "ignored",
                    ignoredAt: Date(timeIntervalSince1970: 10),
                    mode: .untilNextTurn
                )
            ]
        )
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { request in
                    requests.append(request)
                    return []
                },
                initialPreferences: preferences,
                visibleLimit: 8
            )
        }

        await store.refresh()

        try expect(requests.values.first?.includedThreadIDs == ["ignored", "pinned"],
                   "load should include pinned and ignored task IDs")
        try expect(requests.values.first?.favoriteThreadIDs == ["favorite"],
                   "load should request favorites through the archived-aware path")
        try expect(requests.values.first?.recentLimit == 9,
                   "ignored tasks should increase the recent candidate limit")
    },
    TestCase(name: "store pinning reorders same-status tasks and persists") {
        let preferenceHistory = PreferenceHistoryBox()
        let candidates = [
            storeListSnapshot(id: "recent", status: .running, eventSecond: 20),
            storeListSnapshot(id: "older", status: .running, eventSecond: 10)
        ]
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in candidates },
                onPreferencesChange: { preferenceHistory.append($0) }
            )
        }

        await store.refresh()
        await MainActor.run { store.togglePin(for: "older") }

        let result = await MainActor.run { (store.snapshots.map(\.id), store.isPinned("older")) }
        try expect(result.0 == ["older", "recent"], "pin should reorder tasks within one status")
        try expect(result.1, "store should expose pinned state")
        try expect(preferenceHistory.values.last?.pinnedThreadIDs == ["older"],
                   "pin change should be persisted")
    },
    TestCase(name: "store prunes pinned task missing from successful load") {
        let preferenceHistory = PreferenceHistoryBox()
        let preferences = ThreadListPreferences(pinnedThreadIDs: ["archived"])
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in [] },
                initialPreferences: preferences,
                onPreferencesChange: { preferenceHistory.append($0) }
            )
        }

        await store.refresh()

        let isPinned = await MainActor.run { store.isPinned("archived") }
        try expect(!isPinned, "unavailable task should not remain permanently pinned")
        try expect(preferenceHistory.values.last?.pinnedThreadIDs.isEmpty == true,
                   "pruned pin should be persisted")
    },
    TestCase(name: "store toggles favorite and favorites-only mode") {
        let preferenceHistory = PreferenceHistoryBox()
        let candidates = [
            storeListSnapshot(id: "favorite", status: .idle, eventSecond: 10),
            storeListSnapshot(id: "regular", status: .running, eventSecond: 20)
        ]
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in candidates },
                onPreferencesChange: { preferenceHistory.append($0) }
            )
        }

        await store.refresh()
        await MainActor.run {
            store.toggleFavorite(for: "favorite")
            store.toggleFavoritesOnly()
        }

        let result = await MainActor.run {
            (
                store.snapshots.map(\.id),
                store.isFavorite("favorite"),
                store.showsFavoritesOnly
            )
        }
        try expect(result.0 == ["favorite"], "favorites-only mode should update the visible list immediately")
        try expect(result.1, "store should expose favorite state")
        try expect(result.2, "store should expose favorites-only mode")
        try expect(preferenceHistory.values.last?.favoriteThreadIDs == ["favorite"],
                   "favorite state should be persisted")
        try expect(preferenceHistory.values.last?.showsFavoritesOnly == true,
                   "favorites-only mode should be persisted")
    },
    TestCase(name: "store keeps unavailable favorite IDs") {
        let preferences = ThreadListPreferences(favoriteThreadIDs: ["temporarily-missing"])
        let store = await MainActor.run {
            ThreadStatusStore(load: { _ in [] }, initialPreferences: preferences)
        }

        await store.refresh()

        let remainsFavorite = await MainActor.run { store.isFavorite("temporarily-missing") }
        try expect(remainsFavorite, "missing favorite should survive temporary data-source gaps")
    },
    TestCase(name: "store restores archived favorite without unsupported Codex navigation") {
        let archived = storeListSnapshot(
            id: "archived",
            status: .idle,
            eventSecond: 10,
            isArchived: true
        )
        let active = storeListSnapshot(id: "archived", status: .idle, eventSecond: 20)
        let sequence = SnapshotSequence(values: [[archived], [active]])
        let restoredIDs = StringHistoryBox()
        let preferences = ThreadListPreferences(favoriteThreadIDs: ["archived"])
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in await sequence.next() },
                restoreArchive: { threadID in restoredIDs.append(threadID) },
                initialPreferences: preferences
            )
        }

        await store.refresh()
        await store.restoreArchivedFavorite("archived")

        let result = await MainActor.run {
            (
                store.isFavorite("archived"),
                store.archiveRestoreFeedback,
                store.restoringThreadIDs,
                store.snapshots.first?.isArchived
            )
        }
        try expect(restoredIDs.values == ["archived"], "store should invoke restore exactly once")
        try expect(result.0, "successful restore must retain favorite")
        try expect(result.1 == .success(threadID: "archived"), "success feedback should publish")
        try expect(result.2.isEmpty, "restoring state should clear after success")
        try expect(result.3 == false, "successful restore should refresh the SQLite-backed snapshot")
    },
    TestCase(name: "store restore failure preserves list preferences") {
        let archived = storeListSnapshot(
            id: "archived",
            status: .idle,
            eventSecond: 10,
            isArchived: true
        )
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: ["archived"],
            favoriteThreadIDs: ["archived"],
            ignoredRules: [
                "other": IgnoredThreadRule(
                    threadID: "other",
                    ignoredAt: Date(timeIntervalSince1970: 5),
                    mode: .untilNextTurn
                )
            ]
        )
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in [archived] },
                restoreArchive: { _ in throw ArchiveRestoreError.executionFailed("failed") },
                initialPreferences: preferences
            )
        }

        await store.refresh()
        let beforeRestore = await MainActor.run { store.preferences }
        await store.restoreArchivedFavorite("archived")
        let result = await MainActor.run {
            (store.preferences, store.archiveRestoreFeedback, store.restoringThreadIDs)
        }

        try expect(result.0 == beforeRestore, "failed restore must not change list preferences")
        try expect(
            result.1 == .failure(threadID: "archived", message: "恢复失败：failed"),
            "failure feedback should expose the stable localized error"
        )
        try expect(result.2.isEmpty, "restoring state should clear after failure")
    },
    TestCase(name: "store prevents duplicate archive restore") {
        let archived = storeListSnapshot(
            id: "archived",
            status: .idle,
            eventSecond: 10,
            isArchived: true
        )
        let gate = ArchiveRestoreGate()
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in [archived] },
                restoreArchive: { threadID in try await gate.restore(threadID) },
                initialPreferences: ThreadListPreferences(favoriteThreadIDs: ["archived"])
            )
        }

        await store.refresh()
        let firstRestore = Task { await store.restoreArchivedFavorite("archived") }
        await gate.waitUntilStarted()
        await store.restoreArchivedFavorite("archived")

        let isRestoring = await MainActor.run { store.isRestoringArchive("archived") }
        let restoredThreadIDs = await gate.threadIDs
        try expect(isRestoring, "first restore should remain visible while command is running")
        try expect(restoredThreadIDs == ["archived"], "duplicate restore should not invoke CLI twice")

        await gate.release()
        await firstRestore.value
    },
    TestCase(name: "store ignores task immediately and suppresses its notification") {
        let initial = storeListSnapshot(id: "hidden", status: .idle, eventSecond: 10)
        let completed = completedStoreSnapshot(id: "hidden", second: 20)
        let sequence = SnapshotSequence(values: [[initial], [completed]])
        let receivedEvents = EventBox()
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in await sequence.next() },
                now: { Date(timeIntervalSince1970: 15) },
                onNotification: { receivedEvents.append($0) }
            )
        }

        await store.refresh(notificationPolicy: .baseline)
        await MainActor.run { store.ignore("hidden") }
        await store.refresh(notificationPolicy: .notify)

        let result = await MainActor.run { (store.snapshots, store.ignoredThreadIDs) }
        try expect(result.0.isEmpty, "ignored task should disappear immediately")
        try expect(result.1 == ["hidden"], "ignored rule should remain visible to recovery UI")
        try expect(receivedEvents.values.isEmpty, "ignored task should not emit completion sound")
    },
    TestCase(name: "store automatically restores ignored task after new turn") {
        let preferenceHistory = PreferenceHistoryBox()
        let preferences = ThreadListPreferences(
            ignoredRules: [
                "resumed": IgnoredThreadRule(
                    threadID: "resumed",
                    ignoredAt: Date(timeIntervalSince1970: 30),
                    mode: .untilNextTurn
                )
            ]
        )
        let resumed = storeListSnapshot(
            id: "resumed",
            status: .running,
            eventSecond: 41,
            taskStartedSecond: 40
        )
        let store = await MainActor.run {
            ThreadStatusStore(
                load: { _ in [resumed] },
                initialPreferences: preferences,
                onPreferencesChange: { preferenceHistory.append($0) }
            )
        }

        await store.refresh()

        let result = await MainActor.run { (store.snapshots.map(\.id), store.ignoredThreadIDs) }
        try expect(result.0 == ["resumed"], "new turn should make ignored task visible again")
        try expect(result.1.isEmpty, "new turn should remove ignored rule")
        try expect(preferenceHistory.values.last?.ignoredRules.isEmpty == true,
                   "automatic restore should persist the cleared rule")
    },
    TestCase(name: "store restores one or all ignored tasks") {
        let preferences = ThreadListPreferences(
            ignoredRules: [
                "a": IgnoredThreadRule(
                    threadID: "a",
                    ignoredAt: Date(timeIntervalSince1970: 10),
                    mode: .untilNextTurn
                ),
                "b": IgnoredThreadRule(
                    threadID: "b",
                    ignoredAt: Date(timeIntervalSince1970: 10),
                    mode: .untilNextTurn
                )
            ]
        )
        let store = await MainActor.run {
            ThreadStatusStore(load: { _ in [] }, initialPreferences: preferences)
        }

        await MainActor.run { store.restoreIgnored("a") }
        let afterOne = await MainActor.run { store.ignoredThreadIDs }
        await MainActor.run { store.restoreAllIgnored() }
        let afterAll = await MainActor.run { store.ignoredThreadIDs }

        try expect(afterOne == ["b"], "single restore should keep other rules")
        try expect(afterAll.isEmpty, "restore all should clear every ignored rule")
    }
]

private actor SnapshotSequence {
    private var values: [[ThreadSnapshot]]

    init(values: [[ThreadSnapshot]]) {
        self.values = values
    }

    func next() -> [ThreadSnapshot] {
        values.isEmpty ? [] : values.removeFirst()
    }
}

private actor HealthLoadSequence {
    private let success: ThreadStatusLoadResult
    private let failure: ThreadStatusLoadFailure
    private var hasReturnedSuccess = false

    init(success: ThreadStatusLoadResult, failure: ThreadStatusLoadFailure) {
        self.success = success
        self.failure = failure
    }

    func next() throws -> ThreadStatusLoadResult {
        guard hasReturnedSuccess else {
            hasReturnedSuccess = true
            return success
        }
        throw failure
    }
}

private final class EventBox: @unchecked Sendable {
    var values: [SoundNotificationEvent] = []

    func append(_ event: SoundNotificationEvent) {
        values.append(event)
    }
}

private final class EventHistoryBox: @unchecked Sendable {
    var values: [String] = []

    func replace(_ ids: [String]) {
        values = ids
    }
}

private final class ExpansionHistoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Set<String>] = []

    var values: [Set<String>] {
        lock.withLock { storage }
    }

    func append(_ value: Set<String>) {
        lock.withLock { storage.append(value) }
    }
}

private final class LoadRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ThreadLoadRequest] = []

    var values: [ThreadLoadRequest] {
        lock.withLock { storage }
    }

    func append(_ value: ThreadLoadRequest) {
        lock.withLock { storage.append(value) }
    }
}

private final class PreferenceHistoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ThreadListPreferences] = []

    var values: [ThreadListPreferences] {
        lock.withLock { storage }
    }

    func append(_ value: ThreadListPreferences) {
        lock.withLock { storage.append(value) }
    }
}

private final class StringHistoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private actor ArchiveRestoreGate {
    private(set) var threadIDs: [String] = []
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func restore(_ threadID: String) async throws {
        threadIDs.append(threadID)
        started = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor RefreshLoadGate {
    private(set) var requests: [Set<String>] = []
    private var firstLoadStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func load(_ expandedThreadIDs: Set<String>) async -> [ThreadSnapshot] {
        requests.append(expandedThreadIDs)
        guard requests.count == 1 else {
            return []
        }
        firstLoadStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return []
    }

    func waitUntilFirstLoadStarts() async {
        guard !firstLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseFirstLoad() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func completedStoreSnapshot(id: String, second: TimeInterval) -> ThreadSnapshot {
    let date = Date(timeIntervalSince1970: second)
    return ThreadSnapshot(
        id: id,
        title: id,
        status: .justCompleted,
        statusChangedAt: date,
        updatedAt: date,
        latestEventAt: date,
        completionEventAt: date
    )
}

private final class RecoveryCallBox: @unchecked Sendable {
    struct Call {
        let threadID: String
        let prompt: String
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    var values: [Call] {
        lock.withLock { storage }
    }

    func append(threadID: String, prompt: String) {
        lock.withLock {
            storage.append(Call(threadID: threadID, prompt: prompt))
        }
    }
}

private func storeHealthReport(
    taskDatabase: DataSourceHealthStatus,
    renameIndex: DataSourceHealthStatus = .healthy,
    rollout: DataSourceHealthStatus = .healthy,
    serviceLogs: DataSourceHealthStatus = .healthy
) -> DataSourceHealthReport {
    DataSourceHealthReport(
        taskDatabase: taskDatabase,
        renameIndex: renameIndex,
        rollout: rollout,
        serviceLogs: serviceLogs,
        rolloutSuccessCount: 1,
        rolloutFailureCount: 0,
        lastSuccessfulRefreshAt: nil
    )
}

private func storeListSnapshot(
    id: String,
    status: ThreadDisplayStatus,
    eventSecond: TimeInterval,
    taskStartedSecond: TimeInterval? = nil,
    isArchived: Bool = false
) -> ThreadSnapshot {
    let date = Date(timeIntervalSince1970: eventSecond)
    return ThreadSnapshot(
        id: id,
        title: id,
        status: status,
        statusChangedAt: date,
        updatedAt: date,
        latestEventAt: date,
        latestTaskStartedAt: taskStartedSecond.map(Date.init(timeIntervalSince1970:)),
        isArchived: isArchived
    )
}
