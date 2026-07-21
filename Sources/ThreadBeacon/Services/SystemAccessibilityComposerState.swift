import ApplicationServices
import ThreadBeaconCore

enum SystemAccessibilityComposerState {
    static func valueForPreflight(_ composer: AXUIElement) -> String? {
        let value = stringAttribute(composer, kAXValueAttribute as CFString)
        return canTemporarilyReplace(composer, value: value) ? "" : value
    }

    static func canTemporarilyReplace(_ composer: AXUIElement) -> Bool {
        canTemporarilyReplace(
            composer,
            value: stringAttribute(composer, kAXValueAttribute as CFString)
        )
    }

    private static func canTemporarilyReplace(
        _ composer: AXUIElement,
        value: String?
    ) -> Bool {
        AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
            value: value,
            hasVerifiedPlaceholderDescendant: hasVerifiedPlaceholderDescendant(
                composer
            )
        )
    }

    private static func hasVerifiedPlaceholderDescendant(
        _ composer: AXUIElement
    ) -> Bool {
        var stack = children(of: composer)
        var visitedNodeCount = 0

        while let element = stack.popLast(), visitedNodeCount < 100 {
            visitedNodeCount += 1
            let classes = copyAttribute(
                element,
                "AXDOMClassList" as CFString
            ) as? [String] ?? []
            if classes.contains("placeholder"), containsStaticText(element) {
                return true
            }
            stack.append(contentsOf: children(of: element))
        }
        return false
    }

    private static func containsStaticText(_ root: AXUIElement) -> Bool {
        var stack = [root]
        var visitedNodeCount = 0

        while let element = stack.popLast(), visitedNodeCount < 50 {
            visitedNodeCount += 1
            if stringAttribute(element, kAXRoleAttribute as CFString)
                == kAXStaticTextRole as String {
                return true
            }
            stack.append(contentsOf: children(of: element))
        }
        return false
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
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
}
