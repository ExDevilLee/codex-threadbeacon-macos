import AppKit
import ApplicationServices
import ThreadBeaconCore

enum SystemAccessibilityTargetSelector {
    static func select(threadID: String) -> AccessibilityTargetSelectionResult {
        switch SystemAccessibilityTargetAccess.select(threadID: threadID) {
        case let .failed(result):
            result
        case .selected:
            .selected
        }
    }
}

struct AccessibilitySelectedTarget {
    let identity: AccessibilityTargetIdentity
    let composer: AXUIElement
}

enum AccessibilityTargetAccessOutcome {
    case failed(AccessibilityTargetSelectionResult)
    case selected(AccessibilitySelectedTarget)
}

enum SystemAccessibilityTargetAccess {
    static func select(threadID: String) -> AccessibilityTargetAccessOutcome {
        guard AXIsProcessTrusted() else { return .failed(.notAuthorized) }
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first else {
            return .failed(.codexNotRunning)
        }

        let titles: [String: String]
        do {
            titles = try SessionIndexTitleRepository(
                indexURL: CodexPaths.sessionIndexURL
            ).loadLatestTitles()
        } catch {
            return .failed(.sessionIndexUnavailable)
        }

        let identity: AccessibilityTargetIdentity
        switch AccessibilityTargetIdentityResolver.resolve(
            threadID: threadID,
            latestTitles: titles
        ) {
        case .invalidThreadID:
            return .failed(.invalidThreadID)
        case .titleUnavailable:
            return .failed(.titleUnavailable)
        case let .titleNotUnique(count):
            return .failed(.titleNotUnique(count))
        case let .resolved(resolvedIdentity):
            identity = resolvedIdentity
        }

        let application = AXUIElementCreateApplication(codex.processIdentifier)
        let initial = snapshot(root: application, targetTitle: identity.title)
        guard initial.actionableRows.count == 1 else {
            return .failed(.taskRowNotUnique(initial.actionableRows.count))
        }

        guard AXUIElementPerformAction(
            initial.actionableRows[0],
            kAXPressAction as CFString
        ) == .success else {
            return .failed(.selectionFailed)
        }

        waitForWebContentUpdate()
        let selected = snapshot(root: application, targetTitle: identity.title)
        guard selected.headerTitleMatchCount == 1 else {
            return .failed(.targetHeaderNotUnique(selected.headerTitleMatchCount))
        }
        guard selected.textAreas.count == 1 else {
            return .failed(.composerNotUnique(selected.textAreas.count))
        }
        return .selected(AccessibilitySelectedTarget(
            identity: identity,
            composer: selected.textAreas[0]
        ))
    }

    private struct Snapshot {
        var actionableRows: [AXUIElement] = []
        var headerTitleMatchCount = 0
        var textAreas: [AXUIElement] = []
    }

    private static func snapshot(
        root: AXUIElement,
        targetTitle: String
    ) -> Snapshot {
        var snapshot = Snapshot()
        var stack = [root]
        var visitedNodeCount = 0

        while let element = stack.popLast(), visitedNodeCount < 10_000 {
            visitedNodeCount += 1
            let role = stringAttribute(element, kAXRoleAttribute as CFString)
            if role == kAXTextAreaRole as String {
                appendUnique(element, to: &snapshot.textAreas)
            }

            let titleMatches = stringAttribute(element, kAXTitleAttribute as CFString) == targetTitle
            let valueMatches = stringAttribute(element, kAXValueAttribute as CFString) == targetTitle
            if titleMatches || valueMatches {
                if hasAncestorDOMClass(element, className: "app-header-tint") {
                    snapshot.headerTitleMatchCount += 1
                }
                if let row = actionableAncestor(of: element) {
                    appendUnique(row, to: &snapshot.actionableRows)
                }
            }

            stack.append(contentsOf: children(of: element))
        }
        return snapshot
    }

    private static func actionableAncestor(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { return nil }
            if stringAttribute(candidate, kAXRoleAttribute as CFString) == kAXButtonRole as String,
               actionNames(of: candidate).contains(kAXPressAction as String) {
                return candidate
            }
            current = parent(of: candidate)
        }
        return nil
    }

    private static func hasAncestorDOMClass(
        _ element: AXUIElement,
        className: String
    ) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let candidate = current else { return false }
            let classes = copyAttribute(candidate, "AXDOMClassList" as CFString) as? [String] ?? []
            if classes.contains(className) { return true }
            current = parent(of: candidate)
        }
        return false
    }

    private static func appendUnique(
        _ element: AXUIElement,
        to elements: inout [AXUIElement]
    ) {
        guard !elements.contains(where: { CFEqual($0, element) }) else { return }
        elements.append(element)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        copyAttribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(element, kAXParentAttribute as CFString) else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
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

    private static func waitForWebContentUpdate() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}
