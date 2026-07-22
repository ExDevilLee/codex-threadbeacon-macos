import Combine
import Foundation

@MainActor
public final class CompactionHookSettingsStore: ObservableObject {
    @Published public private(set) var status: CompactionHookConfigurationStatus
    @Published public private(set) var lastError: CompactionHookConfigurationError?

    private let manager: CompactionHookConfigurationManager

    public init(manager: CompactionHookConfigurationManager = CompactionHookConfigurationManager()) {
        self.manager = manager
        status = manager.status()
    }

    public func refresh() {
        lastError = nil
        status = manager.status()
    }

    public func install(helperSourceURL: URL) {
        lastError = nil
        do {
            status = try manager.install(helperSourceURL: helperSourceURL)
        } catch let error as CompactionHookConfigurationError {
            lastError = error
            status = manager.status()
        } catch {
            lastError = .writeFailed
            status = manager.status()
        }
    }

    public func uninstall() {
        lastError = nil
        do {
            try manager.uninstall()
            status = manager.status()
        } catch let error as CompactionHookConfigurationError {
            lastError = error
            status = manager.status()
        } catch {
            lastError = .writeFailed
            status = manager.status()
        }
    }
}
