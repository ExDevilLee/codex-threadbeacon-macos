import Foundation

public struct ThreadStatusLoader: Sendable {
    private let loadRecords: @Sendable (Int) throws -> [ThreadRecord]
    private let loadIncludedRecords: @Sendable (Set<String>) throws -> [ThreadRecord]
    private let loadFavoriteRecords: @Sendable (Set<String>) throws -> [ThreadRecord]
    private let loadSubagentRecords: @Sendable (Set<String>) throws -> [String: [SubagentRecord]]
    private let loadIncidents: @Sendable (Set<String>) throws -> [String: ServiceIncident]
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
        let logRepository = LogEventRepository(databaseURL: CodexPaths.logsDatabaseURL)
        self.init(
            loadRecords: { limit in try repository.loadRecent(limit: limit) },
            loadIncludedRecords: { threadIDs in try repository.loadByIDs(Array(threadIDs)) },
            loadFavoriteRecords: { threadIDs in
                try repository.loadByIDsIncludingArchived(Array(threadIDs))
            },
            loadSubagentRecords: { parentIDs in
                try repository.loadDirectSubagents(parentIDs: Array(parentIDs))
            },
            loadIncidents: { threadIDs in
                try logRepository.loadLatestIncidents(threadIDs: threadIDs)
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
        loadIncludedRecords: @escaping @Sendable (Set<String>) throws -> [ThreadRecord] = { _ in [] },
        loadFavoriteRecords: @escaping @Sendable (Set<String>) throws -> [ThreadRecord] = { _ in [] },
        loadSubagentRecords: @escaping @Sendable (Set<String>) throws -> [String: [SubagentRecord]] = { _ in [:] },
        loadIncidents: @escaping @Sendable (Set<String>) throws -> [String: ServiceIncident] = { _ in [:] },
        loadTitleOverrides: @escaping @Sendable () throws -> [String: String] = { [:] },
        observe: @escaping @Sendable (URL) throws -> RolloutObservation,
        now: @escaping @Sendable () -> Date = Date.init,
        completedRetention: TimeInterval = 60,
        runningFreshness: TimeInterval = 120
    ) {
        self.loadRecords = loadRecords
        self.loadIncludedRecords = loadIncludedRecords
        self.loadFavoriteRecords = loadFavoriteRecords
        self.loadSubagentRecords = loadSubagentRecords
        self.loadIncidents = loadIncidents
        self.loadTitleOverrides = loadTitleOverrides
        self.observe = observe
        self.now = now
        self.completedRetention = completedRetention
        self.runningFreshness = runningFreshness
    }

    public func load(limit: Int) async throws -> [ThreadSnapshot] {
        try await load(limit: limit, includedThreadIDs: [], favoriteThreadIDs: [], expandedThreadIDs: [])
    }

    public func load(limit: Int, expandedThreadIDs: Set<String>) async throws -> [ThreadSnapshot] {
        try await load(
            limit: limit,
            includedThreadIDs: [],
            favoriteThreadIDs: [],
            expandedThreadIDs: expandedThreadIDs
        )
    }

    public func load(
        limit: Int,
        includedThreadIDs: Set<String>,
        expandedThreadIDs: Set<String>
    ) async throws -> [ThreadSnapshot] {
        try await load(
            limit: limit,
            includedThreadIDs: includedThreadIDs,
            favoriteThreadIDs: [],
            expandedThreadIDs: expandedThreadIDs
        )
    }

    public func load(
        limit: Int,
        includedThreadIDs: Set<String>,
        favoriteThreadIDs: Set<String>,
        expandedThreadIDs: Set<String>
    ) async throws -> [ThreadSnapshot] {
        let recentRecords = try loadRecords(limit)
        let includedRecords = includedThreadIDs.isEmpty ? [] : try loadIncludedRecords(includedThreadIDs)
        let favoriteRecords = favoriteThreadIDs.isEmpty ? [] : try loadFavoriteRecords(favoriteThreadIDs)
        var recordsByID = Dictionary(uniqueKeysWithValues: recentRecords.map { ($0.id, $0) })
        for record in includedRecords {
            recordsByID[record.id] = record
        }
        for record in favoriteRecords {
            recordsByID[record.id] = record
        }
        let records = Array(recordsByID.values)
        let titleOverrides = (try? loadTitleOverrides()) ?? [:]
        let currentDate = now()
        let visibleThreadIDs = Set(records.map(\.id))
        let activeThreadIDs = Set(records.filter { !$0.isArchived }.map(\.id))
        let incidentsByThread = (try? loadIncidents(activeThreadIDs)) ?? [:]
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
            let incident = activeIncident(
                incidentsByThread[record.id],
                observation: observation
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
                status: record.isArchived ? .idle : (incident.map(displayStatus) ?? state.status),
                statusChangedAt: record.isArchived ? record.updatedAt : (incident?.occurredAt ?? state.changedAt),
                updatedAt: record.updatedAt,
                latestEventAt: observation.latestEventAt,
                latestTaskStartedAt: record.isArchived ? nil : observation.latestTaskStartedAt,
                completionEventAt: record.isArchived || incident != nil ? nil : observation.completionEventAt,
                tokenUsage: tokenUsage,
                subagentCount: record.subagentCount,
                subagents: subagents,
                serviceIncident: record.isArchived ? nil : incident,
                isArchived: record.isArchived
            )
        }
        .sorted(by: snapshotPrecedes)
    }

    private func activeIncident(
        _ incident: ServiceIncident?,
        observation: RolloutObservation
    ) -> ServiceIncident? {
        guard let incident else {
            return nil
        }
        if let latestTaskStartedAt = observation.latestTaskStartedAt,
           latestTaskStartedAt > incident.occurredAt {
            return nil
        }
        if incident.phase == .retrying,
           observation.status == .justCompleted,
           let completedAt = observation.statusChangedAt,
           completedAt > incident.occurredAt {
            return nil
        }
        return incident
    }

    private func displayStatus(for incident: ServiceIncident) -> ThreadDisplayStatus {
        switch incident.phase {
        case .retrying: .warning
        case .failed: .error
        }
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
