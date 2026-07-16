import Foundation

public struct ThreadStatusLoader: Sendable {
    private let loadRecords: @Sendable (Int) throws -> [ThreadRecord]
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
            loadTitleOverrides: { try titleRepository.loadLatestTitles() },
            observe: { url in try parser.parse(fileURL: url) },
            now: now,
            completedRetention: completedRetention,
            runningFreshness: runningFreshness
        )
    }

    public init(
        loadRecords: @escaping @Sendable (Int) throws -> [ThreadRecord],
        loadTitleOverrides: @escaping @Sendable () throws -> [String: String] = { [:] },
        observe: @escaping @Sendable (URL) throws -> RolloutObservation,
        now: @escaping @Sendable () -> Date = Date.init,
        completedRetention: TimeInterval = 60,
        runningFreshness: TimeInterval = 120
    ) {
        self.loadRecords = loadRecords
        self.loadTitleOverrides = loadTitleOverrides
        self.observe = observe
        self.now = now
        self.completedRetention = completedRetention
        self.runningFreshness = runningFreshness
    }

    public func load(limit: Int) async throws -> [ThreadSnapshot] {
        let records = try loadRecords(limit)
        let titleOverrides = (try? loadTitleOverrides()) ?? [:]
        let currentDate = now()

        return records.map { record in
            let observation: RolloutObservation
            do {
                observation = try observe(URL(fileURLWithPath: record.rolloutPath))
            } catch {
                observation = RolloutObservation()
            }

            let status: ThreadDisplayStatus
            let statusChangedAt: Date
            if observation.status == .justCompleted,
               let changedAt = observation.statusChangedAt,
               currentDate.timeIntervalSince(changedAt) > completedRetention {
                status = .idle
                statusChangedAt = changedAt
            } else if observation.status == .running,
                      let latestEventAt = observation.latestEventAt,
                      currentDate.timeIntervalSince(latestEventAt) > runningFreshness {
                status = .unknown
                statusChangedAt = latestEventAt
            } else {
                status = observation.status
                statusChangedAt = observation.statusChangedAt ?? record.updatedAt
            }

            return ThreadSnapshot(
                id: record.id,
                title: titleOverrides[record.id] ?? record.title,
                status: status,
                statusChangedAt: statusChangedAt,
                updatedAt: record.updatedAt,
                latestEventAt: observation.latestEventAt
            )
        }
        .sorted(by: snapshotPrecedes)
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
}
