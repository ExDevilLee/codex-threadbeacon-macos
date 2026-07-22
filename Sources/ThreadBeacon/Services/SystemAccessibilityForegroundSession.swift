import AppKit
import ThreadBeaconCore

@MainActor
struct SystemAccessibilityForegroundSession {
    private static let codexBundleIdentifier = "com.openai.codex"

    private let originalApplication: AccessibilityApplicationIdentity?
    private let codexApplication: AccessibilityApplicationIdentity?

    static func capture() -> Self {
        Self(
            originalApplication: identity(of: NSWorkspace.shared.frontmostApplication),
            codexApplication: identity(
                of: NSRunningApplication.runningApplications(
                    withBundleIdentifier: codexBundleIdentifier
                ).first
            )
        )
    }

    func restoreIfSafe() {
        let runningOriginal = originalApplication.flatMap {
            NSRunningApplication(processIdentifier: $0.processIdentifier)
        }
        let decision = AccessibilityForegroundRestorationPolicy.evaluate(
            mode: .unattended,
            originalApplication: originalApplication,
            currentFrontmostApplication: Self.identity(
                of: NSWorkspace.shared.frontmostApplication
            ),
            codexApplication: codexApplication,
            isOriginalApplicationTerminated: runningOriginal?.isTerminated ?? true
        )
        guard decision == .restore, let runningOriginal else { return }
        _ = runningOriginal.activate(options: [.activateAllWindows])
    }

    private static func identity(
        of application: NSRunningApplication?
    ) -> AccessibilityApplicationIdentity? {
        guard let application else { return nil }
        return AccessibilityApplicationIdentity(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier
        )
    }
}
