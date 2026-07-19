import Foundation

public enum DisplayPreferenceKeys {
    public static let refreshIntervalSeconds = "displayRefreshIntervalSeconds"
    public static let maximumTaskCount = "displayMaximumTaskCount"
    public static let appLanguage = "displayAppLanguage"
    public static let appTheme = "displayAppTheme"
}

public struct DisplaySettingsRepository {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> DisplaySettings {
        DisplaySettings(
            refreshIntervalSeconds: defaults.integer(forKey: DisplayPreferenceKeys.refreshIntervalSeconds),
            maximumTaskCount: defaults.integer(forKey: DisplayPreferenceKeys.maximumTaskCount),
            appLanguage: AppLanguage(
                rawValue: defaults.string(forKey: DisplayPreferenceKeys.appLanguage) ?? ""
            ) ?? .defaultValue
        )
    }

    public func save(_ settings: DisplaySettings) {
        defaults.set(settings.refreshIntervalSeconds, forKey: DisplayPreferenceKeys.refreshIntervalSeconds)
        defaults.set(settings.maximumTaskCount, forKey: DisplayPreferenceKeys.maximumTaskCount)
        defaults.set(settings.appLanguage.rawValue, forKey: DisplayPreferenceKeys.appLanguage)
    }
}
