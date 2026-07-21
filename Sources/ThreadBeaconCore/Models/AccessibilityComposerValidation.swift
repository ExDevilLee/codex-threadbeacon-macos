import Foundation

public enum AccessibilityComposerValidationResult: Equatable, Sendable {
    case notAuthorized
    case codexNotRunning
    case composerNotUnique(Int)
    case composerNotEmpty
    case composerNotSettable
    case writeFailed
    case readbackFailed
    case cleanupFailed
    case verified

    public var isVerified: Bool {
        self == .verified
    }
}

public enum AccessibilityComposerSafetyPolicy {
    public static func canTemporarilyReplace(
        value: String?,
        hasVerifiedPlaceholderDescendant: Bool = false
    ) -> Bool {
        guard let value else { return false }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty
            || normalized == "随心输入"
            || hasVerifiedPlaceholderDescendant
    }
}
