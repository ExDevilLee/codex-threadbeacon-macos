public enum MonitoringMode: Equatable, Sendable {
    case active
    case paused

    public var shouldAutoRefresh: Bool {
        self == .active
    }

    public mutating func toggle() {
        self = self == .active ? .paused : .active
    }
}
