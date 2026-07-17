import Foundation
import ThreadBeaconCore

let threadListPolicyTests = [
    TestCase(name: "thread list keeps status priority above pinning") {
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: ["idle"],
            ignoredRules: [:]
        )
        let result = ThreadListPolicy.evaluate(
            candidates: [
                listSnapshot(id: "idle", status: .idle, eventSecond: 20),
                listSnapshot(id: "error", status: .error, eventSecond: 10)
            ],
            preferences: preferences,
            limit: 8
        )

        try expect(
            result.visibleSnapshots.map(\.id) == ["error", "idle"],
            "an unpinned error should remain above a pinned idle task"
        )
    },
    TestCase(name: "thread list puts pinned tasks first within one status") {
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: ["pinned"],
            ignoredRules: [:]
        )
        let result = ThreadListPolicy.evaluate(
            candidates: [
                listSnapshot(id: "recent", status: .running, eventSecond: 20),
                listSnapshot(id: "pinned", status: .running, eventSecond: 10)
            ],
            preferences: preferences,
            limit: 8
        )

        try expect(
            result.visibleSnapshots.map(\.id) == ["pinned", "recent"],
            "pinning should win over recency only within the same status"
        )
    },
    TestCase(name: "thread list filters ignored task and fills visible limit") {
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: [],
            ignoredRules: [
                "hidden": IgnoredThreadRule(
                    threadID: "hidden",
                    ignoredAt: Date(timeIntervalSince1970: 30),
                    mode: .untilNextTurn
                )
            ]
        )
        let result = ThreadListPolicy.evaluate(
            candidates: [
                listSnapshot(id: "hidden", status: .running, eventSecond: 20),
                listSnapshot(id: "first", status: .idle, eventSecond: 10),
                listSnapshot(id: "second", status: .idle, eventSecond: 9)
            ],
            preferences: preferences,
            limit: 2
        )

        try expect(
            result.visibleSnapshots.map(\.id) == ["first", "second"],
            "ignored task should not consume a visible slot"
        )
        try expect(
            result.ignoredSnapshots.map(\.id) == ["hidden"],
            "ignored snapshot should remain available for recovery UI"
        )
    },
    TestCase(name: "thread list restores ignored task after a newer turn starts") {
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: [],
            ignoredRules: [
                "resumed": IgnoredThreadRule(
                    threadID: "resumed",
                    ignoredAt: Date(timeIntervalSince1970: 30),
                    mode: .untilNextTurn
                ),
                "still-hidden": IgnoredThreadRule(
                    threadID: "still-hidden",
                    ignoredAt: Date(timeIntervalSince1970: 30),
                    mode: .untilNextTurn
                )
            ]
        )
        let result = ThreadListPolicy.evaluate(
            candidates: [
                listSnapshot(
                    id: "resumed",
                    status: .running,
                    eventSecond: 41,
                    taskStartedSecond: 40
                ),
                listSnapshot(
                    id: "still-hidden",
                    status: .running,
                    eventSecond: 30,
                    taskStartedSecond: 29
                )
            ],
            preferences: preferences,
            limit: 8
        )

        try expect(
            result.visibleSnapshots.map(\.id) == ["resumed"],
            "a task_started newer than ignoredAt should restore the task"
        )
        try expect(
            result.preferences.ignoredRules.keys.sorted() == ["still-hidden"],
            "only the rule with a newer turn should be removed"
        )
    },
    TestCase(name: "thread list can show only favorite tasks") {
        let preferences = ThreadListPreferences(
            favoriteThreadIDs: ["favorite", "archived-favorite"],
            showsFavoritesOnly: true
        )
        let result = ThreadListPolicy.evaluate(
            candidates: [
                listSnapshot(id: "regular", status: .running, eventSecond: 30),
                listSnapshot(id: "favorite", status: .idle, eventSecond: 20),
                listSnapshot(id: "archived-favorite", status: .idle, eventSecond: 10, isArchived: true)
            ],
            preferences: preferences,
            limit: 8
        )

        try expect(
            result.visibleSnapshots.map(\.id) == ["favorite", "archived-favorite"],
            "favorites-only mode should hide every non-favorite task"
        )
    }
]

private func listSnapshot(
    id: String,
    status: ThreadDisplayStatus,
    eventSecond: TimeInterval,
    taskStartedSecond: TimeInterval? = nil,
    isArchived: Bool = false
) -> ThreadSnapshot {
    let eventDate = Date(timeIntervalSince1970: eventSecond)
    return ThreadSnapshot(
        id: id,
        title: id,
        status: status,
        statusChangedAt: eventDate,
        updatedAt: eventDate,
        latestEventAt: eventDate,
        latestTaskStartedAt: taskStartedSecond.map(Date.init(timeIntervalSince1970:)),
        isArchived: isArchived
    )
}
