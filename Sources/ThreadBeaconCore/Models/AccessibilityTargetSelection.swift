import Foundation

public struct AccessibilityTargetIdentity: Equatable, Sendable {
    public let threadID: String
    public let title: String

    public init(threadID: String, title: String) {
        self.threadID = threadID
        self.title = title
    }
}

public enum AccessibilityTargetIdentityResolution: Equatable, Sendable {
    case invalidThreadID
    case titleUnavailable
    case resolved(AccessibilityTargetIdentity)
}

public enum AccessibilityTargetIdentityResolver {
    public static func resolve(
        threadID: String,
        latestTitles: [String: String]
    ) -> AccessibilityTargetIdentityResolution {
        let normalizedID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return .invalidThreadID }
        guard let title = latestTitles[normalizedID] else { return .titleUnavailable }
        return .resolved(AccessibilityTargetIdentity(threadID: normalizedID, title: title))
    }
}

public enum AccessibilityThreadDeepLink {
    public static func url(threadID: String) -> URL? {
        let normalizedID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(normalizedID)"
        return components.url
    }
}

public enum AccessibilityVerifiedTargetPolicy {
    public static func canSend(threadID: String, selectedThreadID: String?) -> Bool {
        guard let selectedThreadID else { return false }
        return threadID.trimmingCharacters(in: .whitespacesAndNewlines) == selectedThreadID
    }
}

public enum AccessibilityTargetSelectionResult: Equatable, Sendable {
    case notAuthorized
    case codexNotRunning
    case invalidThreadID
    case sessionIndexUnavailable
    case titleUnavailable
    case selectionFailed
    case targetHeaderNotUnique(Int)
    case composerNotUnique(Int)
    case selected

    public var isSelected: Bool {
        self == .selected
    }
}
