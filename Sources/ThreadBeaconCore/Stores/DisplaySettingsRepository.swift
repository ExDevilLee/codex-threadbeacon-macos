import Foundation

public enum DisplayPreferenceKeys {
    public static let refreshIntervalSeconds = "displayRefreshIntervalSeconds"
    public static let maximumTaskCount = "displayMaximumTaskCount"
}

public struct DisplaySettingsRepository {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> DisplaySettings {
        DisplaySettings(
            refreshIntervalSeconds: defaults.integer(forKey: DisplayPreferenceKeys.refreshIntervalSeconds),
            maximumTaskCount: defaults.integer(forKey: DisplayPreferenceKeys.maximumTaskCount)
        )
    }

    public func save(_ settings: DisplaySettings) {
        defaults.set(settings.refreshIntervalSeconds, forKey: DisplayPreferenceKeys.refreshIntervalSeconds)
        defaults.set(settings.maximumTaskCount, forKey: DisplayPreferenceKeys.maximumTaskCount)
    }
}
