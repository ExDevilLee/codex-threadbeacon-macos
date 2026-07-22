import Foundation

public struct AccessibilityApplicationIdentity: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let processIdentifier: Int32

    public init(bundleIdentifier: String?, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public enum AccessibilityForegroundRestorationDecision: Equatable, Sendable {
    case restore
    case skipUserInitiated
    case skipOriginalApplicationUnavailable
    case skipOriginalApplicationIsCodex
    case skipOriginalApplicationTerminated
    case skipFrontmostApplicationChanged
}

public enum AccessibilityForegroundRestorationPolicy {
    private static let codexBundleIdentifier = "com.openai.codex"

    public static func evaluate(
        mode: AccessibilityInteractionMode,
        originalApplication: AccessibilityApplicationIdentity?,
        currentFrontmostApplication: AccessibilityApplicationIdentity?,
        codexApplication: AccessibilityApplicationIdentity?,
        isOriginalApplicationTerminated: Bool
    ) -> AccessibilityForegroundRestorationDecision {
        guard mode == .unattended else { return .skipUserInitiated }
        guard let originalApplication else {
            return .skipOriginalApplicationUnavailable
        }
        guard originalApplication.bundleIdentifier != codexBundleIdentifier else {
            return .skipOriginalApplicationIsCodex
        }
        guard !isOriginalApplicationTerminated else {
            return .skipOriginalApplicationTerminated
        }
        guard let currentFrontmostApplication, let codexApplication,
              codexApplication.bundleIdentifier == codexBundleIdentifier,
              currentFrontmostApplication == codexApplication else {
            return .skipFrontmostApplicationChanged
        }
        return .restore
    }
}
