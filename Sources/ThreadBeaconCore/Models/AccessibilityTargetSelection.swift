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

public enum AccessibilityInteractionPreflightResult: Equatable, Sendable {
    case safe
    case codexFrontmost
    case sourceComposerNotEmpty
    case sourceComposerNotUnique(Int)
    case sourceComposerValueUnavailable
}

public enum AccessibilityInteractionMode: Equatable, Sendable {
    case userInitiated
    case unattended
}

public enum AccessibilityInteractionPreflight {
    public static func evaluate(
        mode: AccessibilityInteractionMode,
        isCodexFrontmost: Bool,
        isCurrentTargetConfirmed: Bool = false,
        sourceComposerValues: [String?]
    ) -> AccessibilityInteractionPreflightResult {
        if mode == .unattended, isCodexFrontmost {
            guard isCurrentTargetConfirmed else { return .codexFrontmost }
            guard sourceComposerValues.count == 1 else {
                return .sourceComposerNotUnique(sourceComposerValues.count)
            }
        }
        guard sourceComposerValues.count <= 1 else {
            return .sourceComposerNotUnique(sourceComposerValues.count)
        }
        guard sourceComposerValues.allSatisfy({ $0 != nil }) else {
            return .sourceComposerValueUnavailable
        }
        guard sourceComposerValues.allSatisfy({ value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        }) else {
            return .sourceComposerNotEmpty
        }
        return .safe
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
    case codexInteractionInProgress
    case invalidThreadID
    case sessionIndexUnavailable
    case titleUnavailable
    case sourceComposerNotEmpty
    case sourceComposerNotUnique(Int)
    case sourceComposerValueUnavailable
    case selectionFailed
    case targetHeaderNotUnique(Int)
    case composerNotUnique(Int)
    case selected

    public var isSelected: Bool {
        self == .selected
    }

    public var diagnosticCode: String {
        switch self {
        case .notAuthorized:
            "not_authorized"
        case .codexNotRunning:
            "codex_not_running"
        case .codexInteractionInProgress:
            "codex_frontmost"
        case .invalidThreadID:
            "invalid_thread_id"
        case .sessionIndexUnavailable:
            "session_index_unavailable"
        case .titleUnavailable:
            "title_unavailable"
        case .sourceComposerNotEmpty:
            "source_composer_not_empty"
        case let .sourceComposerNotUnique(count):
            "source_composer_count_\(count)"
        case .sourceComposerValueUnavailable:
            "source_composer_value_unavailable"
        case .selectionFailed:
            "deep_link_failed"
        case let .targetHeaderNotUnique(count):
            "target_header_count_\(count)"
        case let .composerNotUnique(count):
            "composer_count_\(count)"
        case .selected:
            "selected"
        }
    }
}
