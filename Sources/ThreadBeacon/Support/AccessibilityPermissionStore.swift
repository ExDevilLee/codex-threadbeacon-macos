import AppKit
import ApplicationServices
import Foundation
import ThreadBeaconCore

@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    private static let diagnosticPrompt = "刚才中断了，请继续未完成的任务"
    @Published private(set) var isAuthorized: Bool
    @Published private(set) var diagnosticResult: AccessibilityDiagnosticResult?
    @Published private(set) var composerValidationResult: AccessibilityComposerValidationResult?
    @Published private(set) var targetSelectionResult: AccessibilityTargetSelectionResult?
    @Published private(set) var recoverySendResult: AccessibilityRecoverySendResult?
    @Published private(set) var taskOpenResult: TaskOpenResult?
    @Published private(set) var isChecking = false
    private var selectedTargetThreadID: String?

    init() {
        isAuthorized = AXIsProcessTrusted()
    }

    func refresh() {
        isAuthorized = AXIsProcessTrusted()
        if !isAuthorized {
            diagnosticResult = nil
            composerValidationResult = nil
            targetSelectionResult = nil
            recoverySendResult = nil
            selectedTargetThreadID = nil
        }
    }

    func requestAuthorization() {
        // Swift 6 treats the SDK's exported CFString variable as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func runReadOnlyDiagnostic() {
        refresh()
        guard isAuthorized else {
            diagnosticResult = .notAuthorized
            return
        }

        isChecking = true
        diagnosticResult = SystemAccessibilityDiagnosticChecker.check()
        isChecking = false
    }

    func runComposerValidation() {
        refresh()
        guard isAuthorized else {
            composerValidationResult = .notAuthorized
            return
        }

        isChecking = true
        composerValidationResult = SystemAccessibilityComposerValidator.validate()
        isChecking = false
    }

    func runTargetSelection(threadID: String) {
        refresh()
        guard isAuthorized else {
            targetSelectionResult = .notAuthorized
            return
        }

        isChecking = true
        let result = SystemAccessibilityTargetSelector.select(threadID: threadID)
        targetSelectionResult = result
        selectedTargetThreadID = result.isSelected
            ? threadID.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        recoverySendResult = nil
        isChecking = false
    }

    func openTask(threadID: String, isArchived: Bool) {
        refresh()
        switch TaskOpenRequestPolicy.evaluate(
            isArchived: isArchived,
            isAuthorized: isAuthorized,
            isInteractionInProgress: isChecking
        ) {
        case .archived:
            taskOpenResult = .archived
        case .notAuthorized:
            taskOpenResult = .notAuthorized
        case .interactionInProgress:
            taskOpenResult = .interactionInProgress
        case .allowed:
            isChecking = true
            defer { isChecking = false }
            let result = SystemAccessibilityTargetSelector.select(threadID: threadID)
            taskOpenResult = result.isSelected ? .opened : .selectionFailed(result)
        }
    }

    func dismissTaskOpenResult() {
        taskOpenResult = nil
    }

    func canSend(to threadID: String) -> Bool {
        AccessibilityVerifiedTargetPolicy.canSend(
            threadID: threadID,
            selectedThreadID: selectedTargetThreadID
        )
    }

    func runRecoverySend(threadID: String) async {
        guard canSend(to: threadID) else {
            recoverySendResult = .targetSelectionFailed(.selectionFailed)
            return
        }

        isChecking = true
        recoverySendResult = await SystemAccessibilityRecoverySender.send(
            threadID: threadID,
            prompt: Self.diagnosticPrompt,
            mode: .userInitiated
        )
        isChecking = false
    }

    func runAutomaticRecovery(
        threadID: String,
        prompt: String
    ) async -> AccessibilityRecoverySendResult? {
        refresh()
        guard isAuthorized, !isChecking else { return nil }

        isChecking = true
        defer { isChecking = false }
        let foregroundSession = SystemAccessibilityForegroundSession.capture()
        let result = await SystemAccessibilityRecoverySender.send(
            threadID: threadID,
            prompt: prompt,
            mode: .unattended
        )
        foregroundSession.restoreIfSafe()
        return result
    }
}
