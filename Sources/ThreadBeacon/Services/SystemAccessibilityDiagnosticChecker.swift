import AppKit
import ApplicationServices
import ThreadBeaconCore

enum SystemAccessibilityDiagnosticChecker {
    static func check() -> AccessibilityDiagnosticResult {
        guard AXIsProcessTrusted() else { return .notAuthorized }
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first else {
            return .codexNotRunning
        }

        let application = AXUIElementCreateApplication(codex.processIdentifier)
        let counts = AccessibilityStructureScanner.scan(
            roots: [application],
            role: accessibilityRole,
            children: accessibilityChildren
        )

        guard counts.visitedNodeCount > 1 else { return .scanFailed }
        return .ready(
            windowCount: counts.windowCount,
            textAreaCount: counts.textAreaCount,
            visitedNodeCount: counts.visitedNodeCount
        )
    }

    private static func accessibilityRole(_ element: AXUIElement) -> String? {
        copyAttribute(element, kAXRoleAttribute as CFString) as? String
    }

    private static func accessibilityChildren(_ element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private static func copyAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }
}
