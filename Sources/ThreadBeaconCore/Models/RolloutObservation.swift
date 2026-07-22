import Foundation

public struct RolloutObservation: Equatable, Sendable {
    public var status: ThreadDisplayStatus
    public var statusChangedAt: Date?
    public var latestEventAt: Date?
    public var completionEventAt: Date?
    public var interruptionEventAt: Date?
    public var latestTaskStartedAt: Date?
    public var tokenUsage: TokenUsageSnapshot?
    public var model: String?
    public var reasoningEffort: String?

    public init(
        status: ThreadDisplayStatus = .unknown,
        statusChangedAt: Date? = nil,
        latestEventAt: Date? = nil,
        completionEventAt: Date? = nil,
        interruptionEventAt: Date? = nil,
        latestTaskStartedAt: Date? = nil,
        tokenUsage: TokenUsageSnapshot? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.status = status
        self.statusChangedAt = statusChangedAt
        self.latestEventAt = latestEventAt
        self.completionEventAt = completionEventAt
        self.interruptionEventAt = interruptionEventAt
        self.latestTaskStartedAt = latestTaskStartedAt
        self.tokenUsage = tokenUsage
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}
