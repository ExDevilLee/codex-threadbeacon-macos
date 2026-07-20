import Foundation

public enum AccessibilityRecoverySendResult: Equatable, Sendable {
    case targetSelectionFailed(AccessibilityTargetSelectionResult)
    case rolloutUnavailable
    case composerNotEmpty
    case composerNotSettable
    case writeFailed
    case readbackFailed
    case cleanupFailed
    case sendButtonNotUnique(Int)
    case sendFailed
    case sentUnconfirmed
    case verified

    public var isVerified: Bool {
        self == .verified
    }

    public var didTriggerSend: Bool {
        switch self {
        case .sentUnconfirmed, .verified:
            true
        default:
            false
        }
    }
}
