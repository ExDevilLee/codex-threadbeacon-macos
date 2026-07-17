public struct SubagentCountLabel: Equatable, Sendable {
    public let countText: String
    public let accessibilityLabel: String

    public init(countText: String, accessibilityLabel: String) {
        self.countText = countText
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum SubagentCountFormatter {
    public static func label(for count: Int) -> SubagentCountLabel? {
        guard count > 0 else { return nil }
        return SubagentCountLabel(
            countText: String(count),
            accessibilityLabel: "\(count) 个 Subagent"
        )
    }
}
