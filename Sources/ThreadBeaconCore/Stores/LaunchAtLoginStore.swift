import Combine
import Foundation

@MainActor
public protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
public final class LaunchAtLoginStore: ObservableObject {
    @Published public private(set) var status: LaunchAtLoginStatus
    @Published public private(set) var errorMessage: String?

    private let manager: any LaunchAtLoginManaging

    public init(manager: any LaunchAtLoginManaging) {
        self.manager = manager
        status = manager.status
    }

    public func refresh() {
        status = manager.status
    }

    public func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled, !status.isRegistered {
                try manager.register()
            } else if !enabled, status.isRegistered {
                try manager.unregister()
            }
        } catch {
            let action = enabled ? "开启" : "关闭"
            errorMessage = "无法\(action)登录时启动：\(error.localizedDescription)"
        }
        refresh()
    }

    public func openSystemSettings() {
        manager.openSystemSettings()
    }

    public func dismissError() {
        errorMessage = nil
    }
}
