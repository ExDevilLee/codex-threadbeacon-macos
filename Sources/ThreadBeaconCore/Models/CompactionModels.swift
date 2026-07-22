import Foundation

public struct CompactionHistory: Equatable, Sendable {
    public let completionCount: Int
    public let lastCompletedAt: Date?

    public init(completionCount: Int = 0, lastCompletedAt: Date? = nil) {
        self.completionCount = max(0, completionCount)
        self.lastCompletedAt = lastCompletedAt
    }
}

public enum CompactionTrigger: String, Codable, Sendable {
    case manual
    case auto
}

public struct CompactionActivity: Equatable, Sendable {
    public let sessionID: String
    public let turnID: String
    public let trigger: CompactionTrigger
    public let startedAt: Date

    public init(
        sessionID: String,
        turnID: String,
        trigger: CompactionTrigger,
        startedAt: Date
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.trigger = trigger
        self.startedAt = startedAt
    }
}
