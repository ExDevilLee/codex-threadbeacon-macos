import Foundation

public struct RolloutObservation: Equatable, Sendable {
    public var status: ThreadDisplayStatus
    public var statusChangedAt: Date?
    public var latestEventAt: Date?
    public var tokenUsage: TokenUsageSnapshot?

    public init(
        status: ThreadDisplayStatus = .unknown,
        statusChangedAt: Date? = nil,
        latestEventAt: Date? = nil,
        tokenUsage: TokenUsageSnapshot? = nil
    ) {
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.latestEventAt = latestEventAt
        self.tokenUsage = tokenUsage
    }
}
