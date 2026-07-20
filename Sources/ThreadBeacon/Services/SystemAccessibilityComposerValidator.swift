import AppKit
import ApplicationServices
import ThreadBeaconCore

enum SystemAccessibilityComposerValidator {
    private static let fixedPrompt = "刚才中断了，请继续未完成的任务"

    static func validate() -> AccessibilityComposerValidationResult {
        guard AXIsProcessTrusted() else { return .notAuthorized }
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first else {
            return .codexNotRunning
        }

        let application = AXUIElementCreateApplication(codex.processIdentifier)
        let composers = elements(withRole: kAXTextAreaRole as String, in: application)
        guard composers.count == 1 else { return .composerNotUnique(composers.count) }

        let composer = composers[0]
        guard AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
            value: stringAttribute(composer, kAXValueAttribute as CFString)
        ) else {
            return .composerNotEmpty
        }
        guard isSettable(composer, kAXValueAttribute as CFString) else {
            return .composerNotSettable
        }

        guard setValue(fixedPrompt, on: composer) else { return .writeFailed }
        waitForWebContentUpdate()
        let writeWasVerified = normalizedValue(of: composer) == fixedPrompt

        guard setValue("", on: composer) else { return .cleanupFailed }
        waitForWebContentUpdate()
        guard AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
            value: stringAttribute(composer, kAXValueAttribute as CFString)
        ) else {
            return .cleanupFailed
        }

        return writeWasVerified ? .verified : .readbackFailed
    }

    private static func elements(
        withRole targetRole: String,
        in root: AXUIElement
    ) -> [AXUIElement] {
        var stack = [root]
        var matches: [AXUIElement] = []
        var visitedNodeCount = 0

        while let element = stack.popLast(), visitedNodeCount < 10_000 {
            visitedNodeCount += 1
            if stringAttribute(element, kAXRoleAttribute as CFString) == targetRole {
                matches.append(element)
            }
            stack.append(contentsOf: children(of: element))
        }
        return matches
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private static func normalizedValue(of element: AXUIElement) -> String {
        (stringAttribute(element, kAXValueAttribute as CFString) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> String? {
        copyAttribute(element, attribute) as? String
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

    private static func isSettable(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func setValue(_ value: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFString
        ) == .success
    }

    private static func waitForWebContentUpdate() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}
