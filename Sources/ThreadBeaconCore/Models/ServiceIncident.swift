import Foundation

public enum ServiceIncidentPhase: Equatable, Sendable {
    case retrying
    case failed
}

public struct ServiceIncident: Equatable, Sendable {
    public let episodeID: String
    public let phase: ServiceIncidentPhase
    public let httpStatusCode: Int?
    public let retryAttempt: Int?
    public let retryLimit: Int?
    public let occurredAt: Date

    public init(
        episodeID: String,
        phase: ServiceIncidentPhase,
        httpStatusCode: Int?,
        retryAttempt: Int?,
        retryLimit: Int?,
        occurredAt: Date
    ) {
        self.episodeID = episodeID
        self.phase = phase
        self.httpStatusCode = httpStatusCode
        self.retryAttempt = retryAttempt
        self.retryLimit = retryLimit
        self.occurredAt = occurredAt
    }
}

public struct LogEventRecord: Equatable, Sendable {
    public let threadID: String
    public let occurredAt: Date
    public let target: String
    public let body: String

    public init(threadID: String, occurredAt: Date, target: String, body: String) {
        self.threadID = threadID
        self.occurredAt = occurredAt
        self.target = target
        self.body = body
    }
}
