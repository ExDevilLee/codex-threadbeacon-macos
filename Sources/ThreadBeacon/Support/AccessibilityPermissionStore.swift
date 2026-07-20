import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    @Published private(set) var isAuthorized: Bool

    init() {
        isAuthorized = AXIsProcessTrusted()
    }

    func refresh() {
        isAuthorized = AXIsProcessTrusted()
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
}
