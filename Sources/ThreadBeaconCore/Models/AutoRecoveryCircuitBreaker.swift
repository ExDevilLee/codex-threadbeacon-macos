import Foundation

public struct AutoRecoveryCircuitState: Identifiable, Codable, Equatable, Sendable {
    public let threadID: String
    public let incidentType: AutoRecoveryIncidentType
    public var attemptCount: Int
    public var lastEpisodeID: String
    public var lastAttemptAt: Date

    public var id: String {
        Self.id(threadID: threadID, incidentType: incidentType)
    }

    public init(
        threadID: String,
        incidentType: AutoRecoveryIncidentType,
        attemptCount: Int,
        lastEpisodeID: String,
        lastAttemptAt: Date
    ) {
        self.threadID = threadID
        self.incidentType = incidentType
        self.attemptCount = max(1, attemptCount)
        self.lastEpisodeID = lastEpisodeID
        self.lastAttemptAt = lastAttemptAt
    }

    public static func id(
        threadID: String,
        incidentType: AutoRecoveryIncidentType
    ) -> String {
        "\(threadID):\(incidentType.rawValue)"
    }
}
