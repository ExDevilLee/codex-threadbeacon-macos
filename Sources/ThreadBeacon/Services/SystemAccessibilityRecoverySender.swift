import ApplicationServices
import Foundation
import ThreadBeaconCore

@MainActor
enum SystemAccessibilityRecoverySender {
    private static let fixedPrompt = "刚才中断了，请继续未完成的任务"
    private static let rolloutConfirmationTimeout: Duration = .seconds(10)

    static func send(
        threadID: String,
        mode: AccessibilityInteractionMode
    ) async -> AccessibilityRecoverySendResult {
        let selectedTarget: AccessibilitySelectedTarget
        switch SystemAccessibilityTargetAccess.select(threadID: threadID, mode: mode) {
        case let .failed(result):
            return .targetSelectionFailed(result)
        case let .selected(target):
            selectedTarget = target
        }

        let rolloutURL: URL
        do {
            guard let record = try SQLiteThreadRepository(
                databaseURL: CodexPaths.stateDatabaseURL
            ).loadByIDs([selectedTarget.identity.threadID]).first else {
                return .rolloutUnavailable
            }
            rolloutURL = URL(fileURLWithPath: record.rolloutPath)
        } catch {
            return .rolloutUnavailable
        }

        let checkpointParser = RolloutRecoveryCheckpointParser(
            expectedUserMessage: fixedPrompt
        )
        guard let baseline = try? checkpointParser.parse(fileURL: rolloutURL) else {
            return .rolloutUnavailable
        }

        let composer = selectedTarget.composer
        guard SystemAccessibilityComposerState.canTemporarilyReplace(composer) else {
            return .composerNotEmpty
        }
        guard isSettable(composer, kAXValueAttribute as CFString) else {
            return .composerNotSettable
        }

        guard setValue(fixedPrompt, on: composer) else { return .writeFailed }
        waitForWebContentUpdate()
        guard normalizedValue(of: composer) == fixedPrompt else {
            return cleanup(composer) ? .readbackFailed : .cleanupFailed
        }

        let buttonLookup = nearestSendButton(to: composer)
        guard let sendButton = buttonLookup.button else {
            return cleanup(composer)
                ? .sendButtonNotUnique(buttonLookup.candidateCount)
                : .cleanupFailed
        }

        guard AXUIElementPerformAction(sendButton, kAXPressAction as CFString) == .success else {
            return cleanup(composer) ? .sendFailed : .cleanupFailed
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: rolloutConfirmationTimeout)
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            guard let checkpoint = try? checkpointParser.parse(fileURL: rolloutURL) else {
                continue
            }
            if checkpoint.confirmsNewTurn(after: baseline) {
                return .verified
            }
        }
        return .sentUnconfirmed
    }

    private struct SendButtonLookup {
        let button: AXUIElement?
        let candidateCount: Int
    }

    private static func nearestSendButton(to composer: AXUIElement) -> SendButtonLookup {
        var current = parent(of: composer)
        for _ in 0..<8 {
            guard let container = current else { break }
            let elements = children(of: container)
            let descriptors = elements.map(buttonDescriptor)
            let candidateIndices = AccessibilitySendButtonPolicy.candidateIndices(
                in: descriptors
            )
            if !candidateIndices.isEmpty {
                let button = candidateIndices.count == 1
                    ? elements[candidateIndices[0]]
                    : nil
                return SendButtonLookup(
                    button: button,
                    candidateCount: candidateIndices.count
                )
            }
            current = parent(of: container)
        }
        return SendButtonLookup(button: nil, candidateCount: 0)
    }

    private static func buttonDescriptor(_ element: AXUIElement) -> AccessibilityButtonDescriptor {
        AccessibilityButtonDescriptor(
            role: stringAttribute(element, kAXRoleAttribute as CFString) ?? "",
            actionNames: actionNames(of: element),
            domClassNames: copyAttribute(
                element,
                "AXDOMClassList" as CFString
            ) as? [String] ?? [],
            isEnabled: boolAttribute(element, kAXEnabledAttribute as CFString) ?? false
        )
    }

    private static func cleanup(_ composer: AXUIElement) -> Bool {
        guard setValue("", on: composer) else { return false }
        waitForWebContentUpdate()
        return SystemAccessibilityComposerState.canTemporarilyReplace(composer)
    }

    private static func normalizedValue(of element: AXUIElement) -> String {
        (stringAttribute(element, kAXValueAttribute as CFString) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func setValue(_ value: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFString
        ) == .success
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
}
