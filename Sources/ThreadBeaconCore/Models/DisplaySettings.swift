public struct DisplaySettings: Equatable, Sendable {
    public static let supportedRefreshIntervalSeconds = [1, 2, 5, 10]
    public static let supportedMaximumTaskCounts = [4, 8, 12, 20]
    public static let defaultRefreshIntervalSeconds = 2
    public static let defaultMaximumTaskCount = 8

    public let refreshIntervalSeconds: Int
    public let maximumTaskCount: Int

    public init(refreshIntervalSeconds: Int, maximumTaskCount: Int) {
        self.refreshIntervalSeconds = Self.supportedRefreshIntervalSeconds.contains(refreshIntervalSeconds)
            ? refreshIntervalSeconds
            : Self.defaultRefreshIntervalSeconds
        self.maximumTaskCount = Self.supportedMaximumTaskCounts.contains(maximumTaskCount)
            ? maximumTaskCount
            : Self.defaultMaximumTaskCount
    }
}
