import Combine
import Foundation

public enum UpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(AvailableUpdate)
    case failed
    case currentVersionUnavailable
}

@MainActor
public final class UpdateCheckStore: ObservableObject {
    public typealias CheckOperation = @Sendable (SemanticVersion) async throws -> AvailableUpdate?

    @Published public private(set) var state: UpdateCheckState = .idle

    private let currentVersion: SemanticVersion?
    private let checkOperation: CheckOperation
    private var hasAutomaticallyChecked = false

    public init(currentVersion: String?, checkOperation: @escaping CheckOperation) {
        self.currentVersion = currentVersion.flatMap(SemanticVersion.init)
        self.checkOperation = checkOperation
    }

    public var availableUpdate: AvailableUpdate? {
        guard case let .updateAvailable(update) = state else { return nil }
        return update
    }

    public func checkAutomatically() async {
        guard !hasAutomaticallyChecked else { return }
        hasAutomaticallyChecked = true
        await check()
    }

    public func checkManually() async {
        await check()
    }

    private func check() async {
        guard state != .checking else { return }
        guard let currentVersion else {
            state = .currentVersionUnavailable
            return
        }

        state = .checking
        do {
            if let update = try await checkOperation(currentVersion) {
                state = .updateAvailable(update)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed
        }
    }
}
