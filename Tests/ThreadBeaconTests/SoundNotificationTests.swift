import Foundation
import ThreadBeaconCore

let soundNotificationTests = [
    TestCase(name: "sound tracker keeps first observation silent") {
        var tracker = SoundNotificationTracker()
        let events = tracker.observe(
            [completedSnapshot(id: "a", second: 10)],
            policy: .baseline
        )

        try expect(events.isEmpty, "baseline must stay silent")
        try expect(tracker.seenEventIDs.count == 1, "baseline should record the event waterline")
    },
    TestCase(name: "sound tracker emits one new done event") {
        var tracker = SoundNotificationTracker()
        _ = tracker.observe([completedSnapshot(id: "a", second: 10)], policy: .baseline)

        let events = tracker.observe(
            [completedSnapshot(id: "a", second: 20)],
            policy: .notify
        )

        try expect(events.map(\.category) == [.done], "new completion should emit done")
        try expect(events.first?.threadID == "a", "event should identify the completed thread")
    },
    TestCase(name: "sound tracker does not replay the same completion") {
        var tracker = SoundNotificationTracker()
        _ = tracker.observe([completedSnapshot(id: "a", second: 20)], policy: .baseline)

        let events = tracker.observe(
            [completedSnapshot(id: "a", second: 20)],
            policy: .notify
        )

        try expect(events.isEmpty, "same completion must not replay")
    },
    TestCase(name: "sound tracker coalesces multiple completions but records all") {
        var tracker = SoundNotificationTracker()
        let events = tracker.observe(
            [
                completedSnapshot(id: "a", second: 20),
                completedSnapshot(id: "b", second: 21)
            ],
            policy: .notify
        )

        try expect(events.count == 1, "one refresh batch should play one sound")
        try expect(tracker.seenEventIDs.count == 2, "all new event IDs should be recorded")
    },
    TestCase(name: "sound tracker bounds event history") {
        var tracker = SoundNotificationTracker(maximumHistoryCount: 2)
        _ = tracker.observe(
            [
                completedSnapshot(id: "a", second: 1),
                completedSnapshot(id: "b", second: 2),
                completedSnapshot(id: "c", second: 3)
            ],
            policy: .baseline
        )

        try expect(tracker.seenEventIDs.count == 2, "event history should remain bounded")
        try expect(tracker.seenEventIDs.first?.hasPrefix("done:b:") == true,
                   "bounded history should keep the newest event IDs")
    }
]

private func completedSnapshot(id: String, second: TimeInterval) -> ThreadSnapshot {
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
