public struct SubagentCountLabel: Equatable, Sendable {
    public let countText: String
    public let activeCount: Int
    public let totalCount: Int

    public init(countText: String, activeCount: Int, totalCount: Int) {
        self.countText = countText
        self.activeCount = activeCount
        self.totalCount = totalCount
    }
}

public enum SubagentCountFormatter {
    public static func label(activeCount: Int, totalCount: Int) -> SubagentCountLabel? {
        let total = max(0, totalCount)
        guard total > 0 else { return nil }
        let active = min(max(0, activeCount), total)
        return SubagentCountLabel(
            countText: "\(active)/\(total)",
            activeCount: active,
            totalCount: total
        )
    }
}
