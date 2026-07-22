import Foundation

public struct CompactionHistory: Equatable, Sendable {
    public let completionCount: Int
    public let lastCompletedAt: Date?

    public init(completionCount: Int = 0, lastCompletedAt: Date? = nil) {
        self.completionCount = max(0, completionCount)
        self.lastCompletedAt = lastCompletedAt
    }
}
