import Foundation

public enum ThreadDisplayStatus: String, CaseIterable, Sendable {
    case error
    case needsAction
    case running
    case justCompleted
    case idle
    case unknown

    public var sortOrder: Int {
        switch self {
        case .error: 0
        case .needsAction: 1
        case .running: 2
        case .justCompleted: 3
        case .idle: 4
        case .unknown: 5
        }
    }
}

public struct ThreadRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let rolloutPath: String
    public let updatedAt: Date
    public let tokensUsed: Int64
    public let subagentCount: Int

    public init(
        id: String,
        title: String,
        rolloutPath: String,
        updatedAt: Date,
        tokensUsed: Int64 = 0,
        subagentCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.rolloutPath = rolloutPath
        self.updatedAt = updatedAt
        self.tokensUsed = tokensUsed
        self.subagentCount = max(0, subagentCount)
    }
}

public struct ThreadSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: ThreadDisplayStatus
    public let statusChangedAt: Date
    public let updatedAt: Date
    public let latestEventAt: Date?
    public let completionEventAt: Date?
    public let tokenUsage: TokenUsageSnapshot?

    public init(
        id: String,
        title: String,
        status: ThreadDisplayStatus,
        statusChangedAt: Date,
        updatedAt: Date,
        latestEventAt: Date?,
        completionEventAt: Date? = nil,
        tokenUsage: TokenUsageSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.updatedAt = updatedAt
        self.latestEventAt = latestEventAt
        self.completionEventAt = completionEventAt
        self.tokenUsage = tokenUsage
    }
}
