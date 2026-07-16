import CodexThreadStatusCore
import Foundation

let threadStatusLoaderTests = [
    TestCase(name: "loader merges fallbacks and sorts status snapshots") {
        let now = Date(timeIntervalSince1970: 1_000)
        let records = [
            ThreadRecord(id: "missing", title: "Missing rollout", rolloutPath: "/tmp/missing", updatedAt: now),
            ThreadRecord(id: "idle", title: "Idle", rolloutPath: "/tmp/idle", updatedAt: now),
            ThreadRecord(id: "completed", title: "Completed", rolloutPath: "/tmp/completed", updatedAt: now),
            ThreadRecord(id: "running", title: "Running", rolloutPath: "/tmp/running", updatedAt: now)
        ]
        let observations = [
            "/tmp/running": RolloutObservation(
                status: .running,
                statusChangedAt: now.addingTimeInterval(-10),
                latestEventAt: now.addingTimeInterval(-5)
            ),
            "/tmp/completed": RolloutObservation(
                status: .justCompleted,
                statusChangedAt: now.addingTimeInterval(-30),
                latestEventAt: now.addingTimeInterval(-30)
            ),
            "/tmp/idle": RolloutObservation(
                status: .justCompleted,
                statusChangedAt: now.addingTimeInterval(-120),
                latestEventAt: now.addingTimeInterval(-120)
            )
        ]
        let loader = ThreadStatusLoader(
            loadRecords: { _ in records },
            observe: { url in
                guard let observation = observations[url.path] else {
                    throw TestFailure(description: "missing rollout")
                }
                return observation
            },
            now: { now },
            completedRetention: 60
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(
            snapshots.map(\.status) == [.running, .justCompleted, .idle, .unknown],
            "snapshots should use status priority and completed retention"
        )
        try expect(snapshots.last?.title == "Missing rollout", "missing rollout should remain visible")
    },
    TestCase(name: "loader sorts equal statuses by latest event then id") {
        let now = Date(timeIntervalSince1970: 2_000)
        let records = [
            ThreadRecord(id: "b", title: "B", rolloutPath: "/tmp/b", updatedAt: now),
            ThreadRecord(id: "a", title: "A", rolloutPath: "/tmp/a", updatedAt: now)
        ]
        let loader = ThreadStatusLoader(
            loadRecords: { _ in records },
            observe: { url in
                RolloutObservation(
                    status: .running,
                    statusChangedAt: now,
                    latestEventAt: url.path == "/tmp/a" ? now : now.addingTimeInterval(-1)
                )
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.map(\.id) == ["a", "b"], "newer event should sort first")
    },
    TestCase(name: "loader downgrades stale unresolved turn to unknown") {
        let now = Date(timeIntervalSince1970: 3_000)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "stale",
                    title: "Stale turn",
                    rolloutPath: "/tmp/stale",
                    updatedAt: now.addingTimeInterval(-180)
                )]
            },
            observe: { _ in
                RolloutObservation(
                    status: .running,
                    statusChangedAt: now.addingTimeInterval(-300),
                    latestEventAt: now.addingTimeInterval(-180)
                )
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.status == .unknown, "stale running evidence should expire")
    },
    TestCase(name: "loader prefers renamed title over original SQLite title") {
        let now = Date(timeIntervalSince1970: 4_000)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "thread-a",
                    title: "Original long prompt",
                    rolloutPath: "/tmp/thread-a",
                    updatedAt: now
                )]
            },
            loadTitleOverrides: { ["thread-a": "Renamed sample task"] },
            observe: { _ in RolloutObservation(status: .idle, statusChangedAt: now) },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.title == "Renamed sample task", "renamed title should override SQLite title")
    }
]
