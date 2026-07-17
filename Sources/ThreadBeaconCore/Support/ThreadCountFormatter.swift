public struct ThreadCountLabel: Equatable, Sendable {
    public let displayText: String
    public let explanation: String

    public init(displayText: String, explanation: String) {
        self.displayText = displayText
        self.explanation = explanation
    }
}

public enum ThreadCountFormatter {
    public static func label(for statuses: [ThreadDisplayStatus]) -> ThreadCountLabel {
        let runningCount = statuses.count(where: { $0 == .running })
        let totalCount = statuses.count
        return ThreadCountLabel(
            displayText: "\(runningCount)/\(totalCount)",
            explanation: "\(runningCount) 个任务正在运行，共显示 \(totalCount) 个任务"
        )
    }
}
