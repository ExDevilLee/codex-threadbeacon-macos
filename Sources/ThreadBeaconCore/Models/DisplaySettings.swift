public struct DisplaySettings: Equatable, Sendable {
    public static let supportedRefreshIntervalSeconds = [1, 2, 5, 10]
    public static let supportedMaximumTaskCounts = [4, 8, 12, 20]
    public static let supportedJustCompletedRetentionMinutes = [1, 2, 3, 4, 5]
    public static let defaultRefreshIntervalSeconds = 2
    public static let defaultMaximumTaskCount = 8
    public static let defaultJustCompletedRetentionMinutes = 1
    public static let defaultColorBlindSafeStatusIndicators = true

    public let refreshIntervalSeconds: Int
    public let maximumTaskCount: Int
    public let appLanguage: AppLanguage
    public let justCompletedRetentionMinutes: Int
    public let colorBlindSafeStatusIndicators: Bool

    public init(
        refreshIntervalSeconds: Int,
        maximumTaskCount: Int,
        appLanguage: AppLanguage = .defaultValue,
        justCompletedRetentionMinutes: Int = Self.defaultJustCompletedRetentionMinutes,
        colorBlindSafeStatusIndicators: Bool = Self.defaultColorBlindSafeStatusIndicators
    ) {
        self.refreshIntervalSeconds = Self.supportedRefreshIntervalSeconds.contains(refreshIntervalSeconds)
            ? refreshIntervalSeconds
            : Self.defaultRefreshIntervalSeconds
        self.maximumTaskCount = Self.supportedMaximumTaskCounts.contains(maximumTaskCount)
            ? maximumTaskCount
            : Self.defaultMaximumTaskCount
        self.appLanguage = appLanguage
        self.justCompletedRetentionMinutes = Self.supportedJustCompletedRetentionMinutes.contains(
            justCompletedRetentionMinutes
        ) ? justCompletedRetentionMinutes : Self.defaultJustCompletedRetentionMinutes
        self.colorBlindSafeStatusIndicators = colorBlindSafeStatusIndicators
    }
}
