import Foundation

public struct RolloutObservation: Equatable, Sendable {
    public var status: ThreadDisplayStatus
    public var statusChangedAt: Date?
    public var latestEventAt: Date?

    public init(
        status: ThreadDisplayStatus = .unknown,
        statusChangedAt: Date? = nil,
        latestEventAt: Date? = nil
    ) {
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.latestEventAt = latestEventAt
    }
}
