import Foundation

public enum ThreadDisplayStatus: String, CaseIterable, Sendable {
    case error
    case needsAction
    case warning
    case running
    case justCompleted
    case idle
    case unknown

    public var sortOrder: Int {
        switch self {
        case .error: 0
        case .needsAction: 1
        case .warning: 2
        case .running: 3
        case .justCompleted: 4
        case .idle: 5
        case .unknown: 6
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
    public let isArchived: Bool

    public init(
        id: String,
        title: String,
        rolloutPath: String,
        updatedAt: Date,
        tokensUsed: Int64 = 0,
        subagentCount: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.rolloutPath = rolloutPath
        self.updatedAt = updatedAt
        self.tokensUsed = tokensUsed
        self.subagentCount = max(0, subagentCount)
        self.isArchived = isArchived
    }
}

public struct SubagentRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let parentID: String
    public let title: String
    public let rolloutPath: String
    public let updatedAt: Date
    public let tokensUsed: Int64
    public let agentNickname: String?
    public let agentRole: String?
    public let model: String?
    public let reasoningEffort: String?

    public init(
        id: String,
        parentID: String,
        title: String,
        rolloutPath: String,
        updatedAt: Date,
        tokensUsed: Int64 = 0,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.rolloutPath = rolloutPath
        self.updatedAt = updatedAt
        self.tokensUsed = tokensUsed
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public struct SubagentSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: ThreadDisplayStatus
    public let statusChangedAt: Date
    public let updatedAt: Date
    public let latestEventAt: Date?
    public let tokenUsage: TokenUsageSnapshot?
    public let agentNickname: String?
    public let agentRole: String?
    public let model: String?
    public let reasoningEffort: String?

    public init(
        id: String,
        title: String,
        status: ThreadDisplayStatus,
        statusChangedAt: Date,
        updatedAt: Date,
        latestEventAt: Date?,
        tokenUsage: TokenUsageSnapshot? = nil,
        agentNickname: String? = nil,
        agentRole: String? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.updatedAt = updatedAt
        self.latestEventAt = latestEventAt
        self.tokenUsage = tokenUsage
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

public struct ThreadSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: ThreadDisplayStatus
    public let statusChangedAt: Date
    public let updatedAt: Date
    public let latestEventAt: Date?
    public let latestTaskStartedAt: Date?
    public let completionEventAt: Date?
    public let tokenUsage: TokenUsageSnapshot?
    public let subagentCount: Int
    public let subagents: [SubagentSnapshot]
    public let serviceIncident: ServiceIncident?
    public let isArchived: Bool

    public init(
        id: String,
        title: String,
        status: ThreadDisplayStatus,
        statusChangedAt: Date,
        updatedAt: Date,
        latestEventAt: Date?,
        latestTaskStartedAt: Date? = nil,
        completionEventAt: Date? = nil,
        tokenUsage: TokenUsageSnapshot? = nil,
        subagentCount: Int = 0,
        subagents: [SubagentSnapshot] = [],
        serviceIncident: ServiceIncident? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.updatedAt = updatedAt
        self.latestEventAt = latestEventAt
        self.latestTaskStartedAt = latestTaskStartedAt
        self.completionEventAt = completionEventAt
        self.tokenUsage = tokenUsage
        self.subagentCount = max(0, subagentCount)
        self.subagents = subagents
        self.serviceIncident = serviceIncident
        self.isArchived = isArchived
    }
}
