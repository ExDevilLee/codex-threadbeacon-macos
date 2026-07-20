import AppKit
import ApplicationServices
import Foundation
import ThreadBeaconCore

@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool
    @Published private(set) var diagnosticResult: AccessibilityDiagnosticResult?
    @Published private(set) var isChecking = false

    init() {
        isAuthorized = AXIsProcessTrusted()
    }

    func refresh() {
        isAuthorized = AXIsProcessTrusted()
        if !isAuthorized {
            diagnosticResult = nil
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
}
