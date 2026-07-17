import ThreadBeaconCore
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
    },
    TestCase(name: "loader retains rollout token details") {
        let now = Date(timeIntervalSince1970: 5_000)
        let cumulative = TokenUsage(
            inputTokens: 800,
            cachedInputTokens: 400,
            outputTokens: 200,
            reasoningOutputTokens: 50,
            totalTokens: 1_000
        )
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "with-details",
                    title: "With details",
                    rolloutPath: "/tmp/details",
                    updatedAt: now,
                    tokensUsed: 999
                )]
            },
            observe: { _ in
                RolloutObservation(
                    tokenUsage: TokenUsageSnapshot(
                        totalTokens: 1_000,
                        cumulative: cumulative,
                        currentTurn: nil,
                        updatedAt: now
                    )
                )
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(
            snapshots.first?.tokenUsage?.cumulative?.outputTokens == 200,
            "loader should retain rollout token details"
        )
        try expect(snapshots.first?.tokenUsage?.totalTokens == 1_000, "rollout total should win over fallback")
    },
    TestCase(name: "loader retains rollout completion event") {
        let now = Date(timeIntervalSince1970: 5_500)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "completed",
                    title: "Completed",
                    rolloutPath: "/tmp/completed",
                    updatedAt: now
                )]
            },
            observe: { _ in
                RolloutObservation(completionEventAt: now)
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.completionEventAt == now, "loader should pass completion evidence to snapshot")
    },
    TestCase(name: "loader falls back to SQLite token total") {
        let now = Date(timeIntervalSince1970: 6_000)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "fallback",
                    title: "Fallback",
                    rolloutPath: "/tmp/fallback",
                    updatedAt: now,
                    tokensUsed: 42_000
                )]
            },
            observe: { _ in RolloutObservation() },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)
        let snapshot = snapshots.first

        try expect(
            snapshot?.tokenUsage?.totalTokens == 42_000,
            "SQLite total should remain available when rollout details are missing"
        )
        try expect(
            snapshot?.tokenUsage?.cumulative == nil,
            "fallback total must not invent breakdown fields"
        )
    },
    TestCase(name: "loader retains direct subagent count") {
        let now = Date(timeIntervalSince1970: 6_500)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 3
                )]
            },
            observe: { _ in RolloutObservation() },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(
            snapshots.first?.subagentCount == 3,
            "loader should pass direct child count to snapshots"
        )
    }
]
