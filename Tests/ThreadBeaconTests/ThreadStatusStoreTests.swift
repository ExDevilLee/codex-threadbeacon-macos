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
            ThreadStatusStore(load: { [snapshot] })
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
                load: { await sequence.next() },
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
