import ThreadBeaconCore
import Foundation

let threadStatusStoreTests = [
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
    TestCase(name: "store passes transient expanded thread IDs to refreshes") {
        let receivedExpansions = ExpansionHistoryBox()
        let store = await MainActor.run {
            ThreadStatusStore(load: { expandedThreadIDs in
                receivedExpansions.append(expandedThreadIDs)
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
            ThreadStatusStore(load: { expandedThreadIDs in
                await gate.load(expandedThreadIDs)
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
