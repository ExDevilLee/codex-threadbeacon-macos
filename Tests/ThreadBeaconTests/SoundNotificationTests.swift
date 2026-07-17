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
    },
    TestCase(name: "sound tracker emits one warning per service incident episode") {
        var tracker = SoundNotificationTracker()
        let retrying = incidentSnapshot(id: "a", episodeID: "turn-a", phase: .retrying, second: 20)
        let failed = incidentSnapshot(id: "a", episodeID: "turn-a", phase: .failed, second: 21)

        let firstEvents = tracker.observe([retrying], policy: .notify)
        let repeatedEvents = tracker.observe([failed], policy: .notify)

        try expect(firstEvents.map(\.category) == [.warning], "new service incident should warn")
        try expect(repeatedEvents.isEmpty, "same episode must not warn again after final failure")
    },
    TestCase(name: "sound tracker prefers service warning over misleading completion") {
        var tracker = SoundNotificationTracker()
        let date = Date(timeIntervalSince1970: 30)
        let incident = ServiceIncident(
            episodeID: "turn-failed",
            phase: .failed,
            httpStatusCode: 503,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: date
        )
        let snapshot = ThreadSnapshot(
            id: "a",
            title: "a",
            status: .error,
            statusChangedAt: date,
            updatedAt: date,
            latestEventAt: date,
            completionEventAt: date,
            serviceIncident: incident
        )

        let events = tracker.observe([snapshot], policy: .notify)

        try expect(events.map(\.category) == [.warning], "service failure must not emit done")
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

private func incidentSnapshot(
    id: String,
    episodeID: String,
    phase: ServiceIncidentPhase,
    second: TimeInterval
) -> ThreadSnapshot {
    let date = Date(timeIntervalSince1970: second)
    return ThreadSnapshot(
        id: id,
        title: id,
        status: phase == .failed ? .error : .warning,
        statusChangedAt: date,
        updatedAt: date,
        latestEventAt: date,
        serviceIncident: ServiceIncident(
            episodeID: episodeID,
            phase: phase,
            httpStatusCode: 503,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: date
        )
    )
}
