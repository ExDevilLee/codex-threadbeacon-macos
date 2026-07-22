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
    TestCase(name: "loader prefers SQLite model metadata and fills missing values from rollout") {
        let now = Date(timeIntervalSince1970: 5_250)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "with-model",
                    title: "With model",
                    rolloutPath: "/tmp/model",
                    updatedAt: now,
                    model: "sqlite-model"
                )]
            },
            observe: { _ in
                RolloutObservation(
                    model: "rollout-model",
                    reasoningEffort: "xhigh"
                )
            },
            now: { now }
        )

        let snapshot = try await loader.load(limit: 8).first

        try expect(snapshot?.model == "sqlite-model", "SQLite should remain the primary model source")
        try expect(snapshot?.reasoningEffort == "xhigh", "rollout should fill missing reasoning effort")
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
    },
    TestCase(name: "loader counts active subagents while parent is collapsed") {
        let now = Date(timeIntervalSince1970: 6_800)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 27
                )]
            },
            loadActiveSubagentCandidates: { parentIDs, cutoff in
                try expect(parentIDs == ["parent"], "visible parents should request candidates")
                try expect(
                    cutoff == now.addingTimeInterval(-120),
                    "candidate cutoff should match running freshness"
                )
                return [
                    "parent": [
                        SubagentActivityCandidate(
                            id: "running-a",
                            parentID: "parent",
                            rolloutPath: "/tmp/running-a",
                            updatedAt: now
                        ),
                        SubagentActivityCandidate(
                            id: "running-b",
                            parentID: "parent",
                            rolloutPath: "/tmp/running-b",
                            updatedAt: now
                        ),
                        SubagentActivityCandidate(
                            id: "completed",
                            parentID: "parent",
                            rolloutPath: "/tmp/completed",
                            updatedAt: now
                        )
                    ]
                ]
            },
            observe: { url in
                if url.lastPathComponent == "completed" {
                    return RolloutObservation(
                        status: .justCompleted,
                        statusChangedAt: now,
                        latestEventAt: now
                    )
                }
                if url.lastPathComponent.hasPrefix("running-") {
                    return RolloutObservation(
                        status: .running,
                        statusChangedAt: now,
                        latestEventAt: now
                    )
                }
                return RolloutObservation(status: .idle, statusChangedAt: now)
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.activeSubagentCount == 2, "two running children should be active")
        try expect(snapshots.first?.subagents.isEmpty == true, "collapsed parent should not load details")
    },
    TestCase(name: "loader excludes stale running subagent from active count") {
        let now = Date(timeIntervalSince1970: 6_900)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 1
                )]
            },
            loadActiveSubagentCandidates: { _, _ in
                [
                    "parent": [
                        SubagentActivityCandidate(
                            id: "stale",
                            parentID: "parent",
                            rolloutPath: "/tmp/stale",
                            updatedAt: now
                        )
                    ]
                ]
            },
            observe: { url in
                url.path == "/tmp/stale"
                    ? RolloutObservation(
                        status: .running,
                        statusChangedAt: now.addingTimeInterval(-121),
                        latestEventAt: now.addingTimeInterval(-121)
                    )
                    : RolloutObservation(status: .idle, statusChangedAt: now)
            },
            now: { now },
            runningFreshness: 120
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.activeSubagentCount == 0, "stale running child should be unknown")
    },
    TestCase(name: "loader caps active subagent count at direct total") {
        let now = Date(timeIntervalSince1970: 6_950)
        let candidates = ["first", "second"].map { id in
            SubagentActivityCandidate(
                id: id,
                parentID: "parent",
                rolloutPath: "/tmp/\(id)",
                updatedAt: now
            )
        }
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 1
                )]
            },
            loadActiveSubagentCandidates: { _, _ in ["parent": candidates] },
            observe: { url in
                url.path == "/tmp/parent"
                    ? RolloutObservation(status: .idle, statusChangedAt: now)
                    : RolloutObservation(status: .running, statusChangedAt: now, latestEventAt: now)
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8)

        try expect(snapshots.first?.activeSubagentCount == 1, "active count must not exceed total")
    },
    TestCase(name: "loader reuses active observation for expanded subagent") {
        let now = Date(timeIntervalSince1970: 6_975)
        let observations = StringIntCounter()
        let child = SubagentRecord(
            id: "child",
            parentID: "parent",
            title: "Child",
            rolloutPath: "/tmp/child",
            updatedAt: now
        )
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 1
                )]
            },
            loadSubagentRecords: { _ in ["parent": [child]] },
            loadActiveSubagentCandidates: { _, _ in
                [
                    "parent": [
                        SubagentActivityCandidate(
                            id: child.id,
                            parentID: child.parentID,
                            rolloutPath: child.rolloutPath,
                            updatedAt: child.updatedAt
                        )
                    ]
                ]
            },
            observe: { url in
                observations.increment(url.path)
                return url.path == child.rolloutPath
                    ? RolloutObservation(status: .running, statusChangedAt: now, latestEventAt: now)
                    : RolloutObservation(status: .idle, statusChangedAt: now)
            },
            now: { now }
        )

        let snapshots = try await loader.load(limit: 8, expandedThreadIDs: ["parent"])

        try expect(snapshots.first?.activeSubagentCount == 1, "expanded child should remain active")
        try expect(snapshots.first?.subagents.first?.status == .running, "details should share the state")
        try expect(
            observations.value(for: child.rolloutPath) == 1,
            "candidate and expanded detail should parse one rollout once per refresh"
        )
    },
    TestCase(name: "loader only loads and sorts subagents for expanded visible parents") {
        let now = Date(timeIntervalSince1970: 7_000)
        let requestedParents = StringSetBox()
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "parent",
                    title: "Parent",
                    rolloutPath: "/tmp/parent",
                    updatedAt: now,
                    subagentCount: 2
                )]
            },
            loadSubagentRecords: { parentIDs in
                requestedParents.replace(parentIDs)
                return [
                    "parent": [
                        SubagentRecord(
                            id: "idle-child",
                            parentID: "parent",
                            title: "Original child title",
                            rolloutPath: "/tmp/idle-child",
                            updatedAt: now,
                            tokensUsed: 20,
                            agentNickname: "idle-agent",
                            agentRole: "explorer",
                            model: "gpt-test",
                            reasoningEffort: "medium"
                        ),
                        SubagentRecord(
                            id: "running-child",
                            parentID: "parent",
                            title: "Running child",
                            rolloutPath: "/tmp/running-child",
                            updatedAt: now,
                            tokensUsed: 30
                        )
                    ]
                ]
            },
            loadTitleOverrides: { ["idle-child": "Renamed child"] },
            observe: { url in
                switch url.path {
                case "/tmp/running-child":
                    RolloutObservation(
                        status: .running,
                        statusChangedAt: now.addingTimeInterval(-10),
                        latestEventAt: now.addingTimeInterval(-5)
                    )
                case "/tmp/idle-child":
                    RolloutObservation(
                        status: .justCompleted,
                        statusChangedAt: now.addingTimeInterval(-120),
                        latestEventAt: now.addingTimeInterval(-120)
                    )
                default:
                    RolloutObservation(status: .idle, statusChangedAt: now)
                }
            },
            now: { now },
            completedRetention: 60
        )

        let snapshots = try await loader.load(
            limit: 8,
            expandedThreadIDs: ["parent", "not-visible"]
        )
        let subagents = snapshots.first?.subagents ?? []

        try expect(requestedParents.values == ["parent"], "only visible expanded parents should load")
        try expect(
            subagents.map(\.id) == ["running-child", "idle-child"],
            "subagents should use status priority"
        )
        try expect(subagents[1].title == "Renamed child", "subagent rename should override SQLite title")
        try expect(subagents[1].status == .idle, "subagents should reuse completion retention")
        try expect(subagents[1].agentRole == "explorer", "subagent details should be retained")
        try expect(subagents[1].tokenUsage?.totalTokens == 20, "SQLite token fallback should be retained")
    },
    TestCase(name: "loader merges explicitly included threads without duplicates") {
        let now = Date(timeIntervalSince1970: 7_500)
        let requestedIDs = StringSetBox()
        let recent = ThreadRecord(
            id: "recent",
            title: "Recent",
            rolloutPath: "/tmp/recent",
            updatedAt: now
        )
        let included = ThreadRecord(
            id: "included",
            title: "Included",
            rolloutPath: "/tmp/included",
            updatedAt: now.addingTimeInterval(-100)
        )
        let loader = ThreadStatusLoader(
            loadRecords: { _ in [recent] },
            loadIncludedRecords: { ids in
                requestedIDs.replace(ids)
                return [recent, included]
            },
            observe: { _ in
                RolloutObservation(
                    status: .idle,
                    statusChangedAt: now,
                    latestEventAt: now
                )
            },
            now: { now }
        )

        let snapshots = try await loader.load(
            limit: 1,
            includedThreadIDs: ["included", "recent"],
            expandedThreadIDs: []
        )

        try expect(requestedIDs.values == ["included", "recent"], "loader should request included IDs")
        try expect(Set(snapshots.map(\.id)) == ["included", "recent"], "records should merge by ID")
        try expect(snapshots.count == 2, "duplicate recent record should be removed")
    },
    TestCase(name: "loader normalizes archived favorites and suppresses notifications") {
        let now = Date(timeIntervalSince1970: 7_700)
        let requestedFavorites = StringSetBox()
        let archived = ThreadRecord(
            id: "archived",
            title: "Archived favorite",
            rolloutPath: "/tmp/archived",
            updatedAt: now.addingTimeInterval(-100),
            tokensUsed: 42,
            isArchived: true
        )
        let loader = ThreadStatusLoader(
            loadRecords: { _ in [] },
            loadFavoriteRecords: { ids in
                requestedFavorites.replace(ids)
                return [archived]
            },
            observe: { _ in
                RolloutObservation(
                    status: .running,
                    statusChangedAt: now.addingTimeInterval(-10),
                    latestEventAt: now.addingTimeInterval(-5),
                    completionEventAt: now.addingTimeInterval(-5)
                )
            },
            now: { now }
        )

        let snapshot = try await loader.load(
            limit: 8,
            includedThreadIDs: [],
            favoriteThreadIDs: ["archived"],
            expandedThreadIDs: []
        ).first

        try expect(requestedFavorites.values == ["archived"], "loader should request favorite IDs separately")
        try expect(snapshot?.isArchived == true, "archived flag should reach the UI snapshot")
        try expect(snapshot?.status == .idle, "archived task must not appear to be running")
        try expect(snapshot?.completionEventAt == nil, "archived task must not emit completion evidence")
        try expect(snapshot?.serviceIncident == nil, "archived task must not expose active incidents")
        try expect(snapshot?.tokenUsage?.totalTokens == 42, "archived task should retain token details")
    },
    TestCase(name: "loader lets final service failure override rollout completion") {
        let now = Date(timeIntervalSince1970: 8_000)
        let incident = ServiceIncident(
            episodeID: "turn-failed",
            phase: .failed,
            httpStatusCode: 503,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: now.addingTimeInterval(-10)
        )
        let loader = incidentLoader(
            now: now,
            incident: incident,
            observation: RolloutObservation(
                status: .running,
                statusChangedAt: now.addingTimeInterval(-100),
                latestEventAt: now.addingTimeInterval(-9),
                completionEventAt: now.addingTimeInterval(-9),
                latestTaskStartedAt: now.addingTimeInterval(-100)
            )
        )

        let snapshot = try await loader.load(limit: 8).first

        try expect(snapshot?.status == .error, "final service failure should override rollout status")
        try expect(snapshot?.serviceIncident == incident, "failure details should reach the snapshot")
        try expect(snapshot?.completionEventAt == nil, "failure must suppress generic completion evidence")
        try expect(snapshot?.statusChangedAt == incident.occurredAt, "failure time should drive duration")
    },
    TestCase(name: "loader exposes active service retry as warning") {
        let now = Date(timeIntervalSince1970: 9_000)
        let incident = ServiceIncident(
            episodeID: "turn-retrying",
            phase: .retrying,
            httpStatusCode: 429,
            retryAttempt: 3,
            retryLimit: 5,
            occurredAt: now.addingTimeInterval(-5)
        )
        let loader = incidentLoader(
            now: now,
            incident: incident,
            observation: RolloutObservation(
                status: .running,
                statusChangedAt: now.addingTimeInterval(-20),
                latestEventAt: now.addingTimeInterval(-5),
                latestTaskStartedAt: now.addingTimeInterval(-20)
            )
        )

        let snapshot = try await loader.load(limit: 8).first

        try expect(snapshot?.status == .warning, "active retry should use warning status")
        try expect(snapshot?.serviceIncident == incident, "retry details should reach the snapshot")
    },
    TestCase(name: "loader clears old service incident after a newer task starts") {
        let now = Date(timeIntervalSince1970: 10_000)
        let incident = ServiceIncident(
            episodeID: "old-turn",
            phase: .failed,
            httpStatusCode: 503,
            retryAttempt: 5,
            retryLimit: 5,
            occurredAt: now.addingTimeInterval(-30)
        )
        let loader = incidentLoader(
            now: now,
            incident: incident,
            observation: RolloutObservation(
                status: .running,
                statusChangedAt: now.addingTimeInterval(-10),
                latestEventAt: now.addingTimeInterval(-5),
                latestTaskStartedAt: now.addingTimeInterval(-10)
            )
        )

        let snapshot = try await loader.load(limit: 8).first

        try expect(snapshot?.status == .running, "new task_started should restore rollout status")
        try expect(snapshot?.serviceIncident == nil, "old incident details should be cleared")
    },
    TestCase(name: "loader reports optional data source degradation without dropping tasks") {
        let now = Date(timeIntervalSince1970: 11_000)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [ThreadRecord(
                    id: "visible",
                    title: "Original title",
                    rolloutPath: "/tmp/visible",
                    updatedAt: now
                )]
            },
            loadIncidents: { _ in
                throw TestFailure(description: "logs unavailable")
            },
            loadTitleOverrides: {
                throw TestFailure(description: "index unavailable")
            },
            observe: { _ in RolloutObservation(status: .idle, statusChangedAt: now) },
            now: { now }
        )

        let result = try await loader.loadResult(
            limit: 8,
            includedThreadIDs: [],
            favoriteThreadIDs: [],
            expandedThreadIDs: []
        )

        try expect(result.snapshots.first?.title == "Original title", "rename failure should use fallback title")
        try expect(
            result.health.renameIndex == .degraded("Rename 索引不可用，已回退原始标题"),
            "rename failure should be visible"
        )
        try expect(
            result.health.serviceLogs == .degraded("服务异常日志不可用，服务错误状态可能缺失"),
            "log failure should be visible"
        )
        try expect(result.health.overallStatus == .degraded, "optional failures should degrade health")
    },
    TestCase(name: "loader counts successful and failed rollout reads") {
        let now = Date(timeIntervalSince1970: 12_000)
        let loader = ThreadStatusLoader(
            loadRecords: { _ in
                [
                    ThreadRecord(id: "ok", title: "OK", rolloutPath: "/tmp/ok", updatedAt: now),
                    ThreadRecord(id: "failed", title: "Failed", rolloutPath: "/tmp/failed", updatedAt: now)
                ]
            },
            observe: { url in
                guard url.path == "/tmp/ok" else {
                    throw TestFailure(description: "rollout unavailable")
                }
                return RolloutObservation(status: .idle, statusChangedAt: now)
            },
            now: { now }
        )

        let result = try await loader.loadResult(
            limit: 8,
            includedThreadIDs: [],
            favoriteThreadIDs: [],
            expandedThreadIDs: []
        )

        try expect(result.snapshots.count == 2, "rollout failure should not remove the task")
        try expect(result.health.rolloutSuccessCount == 1, "successful rollout reads should be counted")
        try expect(result.health.rolloutFailureCount == 1, "failed rollout reads should be counted")
        try expect(
            result.health.rollout == .degraded("1 个任务的 Rollout 不可用，状态可能回退"),
            "partial rollout failure should degrade health"
        )
    },
    TestCase(name: "loader reports task database failure as unavailable") {
        let loader = ThreadStatusLoader(
            loadRecords: { _ in throw TestFailure(description: "database unavailable") },
            observe: { _ in RolloutObservation() }
        )

        do {
            _ = try await loader.loadResult(
                limit: 8,
                includedThreadIDs: [],
                favoriteThreadIDs: [],
                expandedThreadIDs: []
            )
            throw TestFailure(description: "expected task database failure")
        } catch let error as ThreadStatusLoadFailure {
            try expect(error.health.overallStatus == .unavailable, "core failure should be unavailable")
            try expect(error.health.renameIndex == .notUsed, "later sources should remain not used")
            try expect(error.localizedDescription == "Codex 任务数据库不可用", "error should be sanitized")
        }
    }
]

private func incidentLoader(
    now: Date,
    incident: ServiceIncident,
    observation: RolloutObservation
) -> ThreadStatusLoader {
    ThreadStatusLoader(
        loadRecords: { _ in
            [ThreadRecord(
                id: "parent",
                title: "Parent",
                rolloutPath: "/tmp/parent",
                updatedAt: now
            )]
        },
        loadIncidents: { _ in ["parent": incident] },
        observe: { _ in observation },
        now: { now }
    )
}

private final class StringSetBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    var values: Set<String> {
        lock.withLock { storage }
    }

    func replace(_ values: Set<String>) {
        lock.withLock { storage = values }
    }
}

private final class StringIntCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Int] = [:]

    func increment(_ key: String) {
        lock.withLock { storage[key, default: 0] += 1 }
    }

    func value(for key: String) -> Int {
        lock.withLock { storage[key, default: 0] }
    }
}
