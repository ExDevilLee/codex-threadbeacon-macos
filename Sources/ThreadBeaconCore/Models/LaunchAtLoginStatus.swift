public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    public var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }

    public var needsApproval: Bool {
        self == .requiresApproval
    }
}
