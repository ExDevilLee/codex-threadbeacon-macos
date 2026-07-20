import Foundation

public enum AccessibilityDiagnosticResult: Equatable, Sendable {
    case notAuthorized
    case codexNotRunning
    case ready(windowCount: Int, textAreaCount: Int, visitedNodeCount: Int)
    case scanFailed

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var windowCount: Int? {
        guard case let .ready(windowCount, _, _) = self else { return nil }
        return windowCount
    }

    public var textAreaCount: Int? {
        guard case let .ready(_, textAreaCount, _) = self else { return nil }
        return textAreaCount
    }

    public var visitedNodeCount: Int? {
        guard case let .ready(_, _, visitedNodeCount) = self else { return nil }
        return visitedNodeCount
    }
}
