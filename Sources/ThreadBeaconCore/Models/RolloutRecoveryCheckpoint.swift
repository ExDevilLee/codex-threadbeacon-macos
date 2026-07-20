import Foundation

public struct RolloutRecoveryCheckpoint: Equatable, Sendable {
    public let latestUserMessageAt: Date?
    public let latestTaskStartedAt: Date?

    public init(latestUserMessageAt: Date?, latestTaskStartedAt: Date?) {
        self.latestUserMessageAt = latestUserMessageAt
        self.latestTaskStartedAt = latestTaskStartedAt
    }

    public func confirmsNewTurn(after baseline: RolloutRecoveryCheckpoint) -> Bool {
        isNewer(latestUserMessageAt, than: baseline.latestUserMessageAt)
            && isNewer(latestTaskStartedAt, than: baseline.latestTaskStartedAt)
    }

    private func isNewer(_ candidate: Date?, than baseline: Date?) -> Bool {
        guard let candidate else { return false }
        guard let baseline else { return true }
        return candidate > baseline
    }
}
