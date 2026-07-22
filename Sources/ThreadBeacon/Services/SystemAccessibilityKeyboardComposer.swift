import AppKit
import ApplicationServices
import Foundation

@MainActor
enum SystemAccessibilityKeyboardComposer {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let webContentDelay = 0.2

    static func type(_ text: String, into composer: AXUIElement) -> Bool {
        guard !text.isEmpty,
              isCodexFrontmost,
              focus(composer),
              postUnicode(text) else {
            return false
        }
        waitForWebContentUpdate()
        return normalizedValue(of: composer) == text
    }

    static func clear(_ composer: AXUIElement) -> Bool {
        guard isCodexFrontmost,
              focus(composer),
              postKey(virtualKey: 0, flags: .maskCommand),
              postKey(virtualKey: 51) else {
            return false
        }
        waitForWebContentUpdate()
        return SystemAccessibilityComposerState.canTemporarilyReplace(composer)
    }

    static func submit(_ composer: AXUIElement) -> Bool {
        guard isCodexFrontmost, focus(composer) else { return false }
        return postKey(virtualKey: 36)
    }

    private static var isCodexFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == codexBundleIdentifier
    }

    private static func focus(_ composer: AXUIElement) -> Bool {
        guard AXUIElementSetAttributeValue(
            composer,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success else {
            return false
        }
        waitForWebContentUpdate()
        return boolAttribute(composer, kAXFocusedAttribute as CFString) == true
    }

    private static func postUnicode(_ text: String) -> Bool {
        let utf16 = Array(text.utf16)
        return utf16.withUnsafeBufferPointer { buffer in
            guard let address = buffer.baseAddress,
                  let keyDown = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 0,
                    keyDown: true
                  ),
                  let keyUp = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 0,
                    keyDown: false
                  ) else {
                return false
            }
            keyDown.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: address
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: address
            )
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            return true
        }
    }

    private static func postKey(
        virtualKey: CGKeyCode,
        flags: CGEventFlags = []
    ) -> Bool {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: virtualKey,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: virtualKey,
            keyDown: false
        ) else {
            return false
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
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

    private static func boolAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Bool? {
        copyAttribute(element, attribute) as? Bool
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

    private static func waitForWebContentUpdate() {
        RunLoop.current.run(until: Date().addingTimeInterval(webContentDelay))
    }
}
