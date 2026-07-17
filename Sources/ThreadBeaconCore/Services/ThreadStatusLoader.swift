import Foundation

public struct ThreadStatusLoader: Sendable {
    private let loadRecords: @Sendable (Int) throws -> [ThreadRecord]
    private let loadSubagentRecords: @Sendable (Set<String>) throws -> [String: [SubagentRecord]]
    private let loadTitleOverrides: @Sendable () throws -> [String: String]
    private let observe: @Sendable (URL) throws -> RolloutObservation
    private let now: @Sendable () -> Date
    private let completedRetention: TimeInterval
    private let runningFreshness: TimeInterval

    public init(
        repository: SQLiteThreadRepository,
        parser: RolloutTailParser = RolloutTailParser(),
        now: @escaping @Sendable () -> Date = Date.init,
        completedRetention: TimeInterval = 60,
        runningFreshness: TimeInterval = 120
    ) {
        let titleRepository = SessionIndexTitleRepository(indexURL: CodexPaths.sessionIndexURL)
        self.init(
            loadRecords: { limit in try repository.loadRecent(limit: limit) },
            loadSubagentRecords: { parentIDs in
                try repository.loadDirectSubagents(parentIDs: Array(parentIDs))
            },
            loadTitleOverrides: { try titleRepository.loadLatestTitles() },
            observe: { url in try parser.parse(fileURL: url) },
            now: now,
            completedRetention: completedRetention,
            runningFreshness: runningFreshness
        )
    }

    public init(
        loadRecords: @escaping @Sendable (Int) throws -> [ThreadRecord],
        loadSubagentRecords: @escaping @Sendable (Set<String>) throws -> [String: [SubagentRecord]] = { _ in [:] },
        loadTitleOverrides: @escaping @Sendable () throws -> [String: String] = { [:] },
        observe: @escaping @Sendable (URL) throws -> RolloutObservation,
        now: @escaping @Sendable () -> Date = Date.init,
        completedRetention: TimeInterval = 60,
        runningFreshness: TimeInterval = 120
    ) {
        self.loadRecords = loadRecords
        self.loadSubagentRecords = loadSubagentRecords
        self.loadTitleOverrides = loadTitleOverrides
        self.observe = observe
        self.now = now
        self.completedRetention = completedRetention
        self.runningFreshness = runningFreshness
    }

    public func load(limit: Int) async throws -> [ThreadSnapshot] {
        try await load(limit: limit, expandedThreadIDs: [])
    }

    public func load(limit: Int, expandedThreadIDs: Set<String>) async throws -> [ThreadSnapshot] {
        let records = try loadRecords(limit)
        let titleOverrides = (try? loadTitleOverrides()) ?? [:]
        let currentDate = now()
        let visibleThreadIDs = Set(records.map(\.id))
        let requestedParentIDs = expandedThreadIDs.intersection(visibleThreadIDs)
        let subagentRecordsByParent = requestedParentIDs.isEmpty
            ? [:]
            : try loadSubagentRecords(requestedParentIDs)

        return records.map { record in
            let observation: RolloutObservation
            do {
                observation = try observe(URL(fileURLWithPath: record.rolloutPath))
            } catch {
                observation = RolloutObservation()
            }

            let state = displayState(
                for: observation,
                fallbackDate: record.updatedAt,
                currentDate: currentDate
            )
            let tokenUsage = tokenUsage(for: observation, fallbackTokens: record.tokensUsed)
            let subagents = (subagentRecordsByParent[record.id] ?? [])
                .map { subagent in
                    makeSubagentSnapshot(
                        from: subagent,
                        titleOverrides: titleOverrides,
                        currentDate: currentDate
                    )
                }
                .sorted(by: subagentPrecedes)

            return ThreadSnapshot(
                id: record.id,
                title: titleOverrides[record.id] ?? record.title,
                status: state.status,
                statusChangedAt: state.changedAt,
                updatedAt: record.updatedAt,
                latestEventAt: observation.latestEventAt,
                completionEventAt: observation.completionEventAt,
                tokenUsage: tokenUsage,
                subagentCount: record.subagentCount,
                subagents: subagents
            )
        }
        .sorted(by: snapshotPrecedes)
    }

    private func makeSubagentSnapshot(
        from record: SubagentRecord,
        titleOverrides: [String: String],
        currentDate: Date
    ) -> SubagentSnapshot {
        let observation: RolloutObservation
        do {
            observation = try observe(URL(fileURLWithPath: record.rolloutPath))
        } catch {
            observation = RolloutObservation()
        }
        let state = displayState(
            for: observation,
            fallbackDate: record.updatedAt,
            currentDate: currentDate
        )
        let fallbackTitle = record.title.isEmpty ? (record.agentNickname ?? "") : record.title

        return SubagentSnapshot(
            id: record.id,
            title: titleOverrides[record.id] ?? fallbackTitle,
            status: state.status,
            statusChangedAt: state.changedAt,
            updatedAt: record.updatedAt,
            latestEventAt: observation.latestEventAt,
            tokenUsage: tokenUsage(for: observation, fallbackTokens: record.tokensUsed),
            agentNickname: record.agentNickname,
            agentRole: record.agentRole,
            model: record.model,
            reasoningEffort: record.reasoningEffort
        )
    }

    private func displayState(
        for observation: RolloutObservation,
        fallbackDate: Date,
        currentDate: Date
    ) -> (status: ThreadDisplayStatus, changedAt: Date) {
        if observation.status == .justCompleted,
           let changedAt = observation.statusChangedAt,
           currentDate.timeIntervalSince(changedAt) > completedRetention {
            return (.idle, changedAt)
        }
        if observation.status == .running,
           let latestEventAt = observation.latestEventAt,
           currentDate.timeIntervalSince(latestEventAt) > runningFreshness {
            return (.unknown, latestEventAt)
        }
        return (observation.status, observation.statusChangedAt ?? fallbackDate)
    }

    private func tokenUsage(
        for observation: RolloutObservation,
        fallbackTokens: Int64
    ) -> TokenUsageSnapshot? {
        observation.tokenUsage ?? (fallbackTokens > 0
            ? TokenUsageSnapshot(
                totalTokens: fallbackTokens,
                cumulative: nil,
                currentTurn: nil,
                updatedAt: nil
            )
            : nil)
    }

    private func snapshotPrecedes(_ lhs: ThreadSnapshot, _ rhs: ThreadSnapshot) -> Bool {
        if lhs.status.sortOrder != rhs.status.sortOrder {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }
        let lhsEvent = lhs.latestEventAt ?? .distantPast
        let rhsEvent = rhs.latestEventAt ?? .distantPast
        if lhsEvent != rhsEvent {
            return lhsEvent > rhsEvent
        }
        return lhs.id < rhs.id
    }

    private func subagentPrecedes(_ lhs: SubagentSnapshot, _ rhs: SubagentSnapshot) -> Bool {
        if lhs.status.sortOrder != rhs.status.sortOrder {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }
        let lhsEvent = lhs.latestEventAt ?? .distantPast
        let rhsEvent = rhs.latestEventAt ?? .distantPast
        if lhsEvent != rhsEvent {
            return lhsEvent > rhsEvent
        }
        return lhs.id < rhs.id
    }
}
