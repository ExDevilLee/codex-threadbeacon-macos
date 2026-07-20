import AppKit
import ApplicationServices
import Foundation
import ThreadBeaconCore

@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool
    @Published private(set) var diagnosticResult: AccessibilityDiagnosticResult?
    @Published private(set) var composerValidationResult: AccessibilityComposerValidationResult?
    @Published private(set) var targetSelectionResult: AccessibilityTargetSelectionResult?
    @Published private(set) var isChecking = false

    init() {
        isAuthorized = AXIsProcessTrusted()
    }

    func refresh() {
        isAuthorized = AXIsProcessTrusted()
        if !isAuthorized {
            diagnosticResult = nil
            composerValidationResult = nil
            targetSelectionResult = nil
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
        targetSelectionResult = SystemAccessibilityTargetSelector.select(threadID: threadID)
        isChecking = false
    }
}
