import Foundation
import ThreadBeaconCore

let launchAtLoginTests = [
    TestCase(name: "launch at login status distinguishes registration and approval") {
        try expect(!LaunchAtLoginStatus.notRegistered.isRegistered,
                   "not registered should keep the toggle off")
        try expect(LaunchAtLoginStatus.enabled.isRegistered,
                   "enabled should keep the toggle on")
        try expect(LaunchAtLoginStatus.requiresApproval.isRegistered,
                   "approval-required services are still registered")
        try expect(LaunchAtLoginStatus.requiresApproval.needsApproval,
                   "approval-required status should expose its action")
    },
    TestCase(name: "launch at login store registers and refreshes system status") {
        let manager = await MainActor.run {
            LaunchAtLoginManagerStub(status: .notRegistered)
        }
        let store = await MainActor.run {
            LaunchAtLoginStore(manager: manager)
        }

        await MainActor.run { store.setEnabled(true) }
        let result = await MainActor.run {
            (store.status, manager.registerCallCount, store.errorMessage)
        }

        try expect(result.0 == .enabled, "store should publish the refreshed enabled status")
        try expect(result.1 == 1, "enabling should register once")
        try expect(result.2 == nil, "successful registration should not expose an error")
    },
    TestCase(name: "launch at login store unregisters approval-required services") {
        let manager = await MainActor.run {
            LaunchAtLoginManagerStub(status: .requiresApproval)
        }
        let store = await MainActor.run {
            LaunchAtLoginStore(manager: manager)
        }

        await MainActor.run { store.setEnabled(false) }
        let result = await MainActor.run {
            (store.status, manager.unregisterCallCount)
        }

        try expect(result.0 == .notRegistered, "disabling should publish not registered")
        try expect(result.1 == 1, "approval-required services should still unregister")
    },
    TestCase(name: "launch at login store exposes registration failure") {
        let manager = await MainActor.run {
            LaunchAtLoginManagerStub(
                status: .notRegistered,
                registerError: LaunchAtLoginStubError.failed
            )
        }
        let store = await MainActor.run {
            LaunchAtLoginStore(manager: manager)
        }

        await MainActor.run { store.setEnabled(true) }
        let result = await MainActor.run {
            (store.status, store.errorMessage)
        }

        try expect(result.0 == .notRegistered, "failed registration should retain system status")
        try expect(result.1 == "无法开启登录时启动：测试失败",
                   "failure should explain which action failed")
    }
]

private enum LaunchAtLoginStubError: LocalizedError {
    case failed

    var errorDescription: String? { "测试失败" }
}

@MainActor
private final class LaunchAtLoginManagerStub: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus
    private let registerError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus, registerError: Error? = nil) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }

    func openSystemSettings() {}
}
