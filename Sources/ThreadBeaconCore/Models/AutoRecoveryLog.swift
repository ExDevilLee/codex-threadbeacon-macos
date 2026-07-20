import Foundation

public enum AutoRecoveryLogStatus: String, Codable, Equatable, Sendable {
    case sending
    case succeeded
    case failed
    case skipped
}

public struct AutoRecoveryLogEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let threadID: String
    public let episodeID: String
    public let incident: String
    public let prompt: String
    public let occurredAt: Date
    public var completedAt: Date?
    public var status: AutoRecoveryLogStatus
    public var detail: String?

    public init(
        id: UUID = UUID(),
        threadID: String,
        episodeID: String,
        incident: String,
        prompt: String,
        occurredAt: Date,
        completedAt: Date? = nil,
        status: AutoRecoveryLogStatus = .sending,
        detail: String? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.episodeID = episodeID
        self.incident = incident
        self.prompt = prompt
        self.occurredAt = occurredAt
        self.completedAt = completedAt
        self.status = status
        self.detail = detail
    }
}
