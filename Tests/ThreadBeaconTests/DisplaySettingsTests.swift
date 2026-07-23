import ThreadBeaconCore
import Foundation

let displaySettingsTests = [
    TestCase(name: "display settings preserve supported values") {
        let settings = DisplaySettings(
            refreshIntervalSeconds: 5,
            maximumTaskCount: 12,
            justCompletedRetentionMinutes: 5
        )

        try expect(settings.refreshIntervalSeconds == 5, "supported refresh interval should be retained")
        try expect(settings.maximumTaskCount == 12, "supported task count should be retained")
        try expect(
            settings.justCompletedRetentionMinutes == 5,
            "supported completed retention should be retained"
        )
        try expect(settings.appLanguage == .system, "language should default to system")
        try expect(
            settings.colorBlindSafeStatusIndicators,
            "color-blind-safe status indicators should default to enabled"
        )
    },
    TestCase(name: "display settings preserve color blind safe status preference") {
        let settings = DisplaySettings(
            refreshIntervalSeconds: 5,
            maximumTaskCount: 12,
            justCompletedRetentionMinutes: 3,
            colorBlindSafeStatusIndicators: true
        )

        try expect(
            settings.colorBlindSafeStatusIndicators,
            "explicit color-blind-safe status preference should be retained"
        )
        try expect(
            settings.justCompletedRetentionMinutes == 3,
            "explicit completed retention should be retained"
        )
    },
    TestCase(name: "display settings replace unsupported values with defaults") {
        let settings = DisplaySettings(
            refreshIntervalSeconds: 3,
            maximumTaskCount: 99,
            justCompletedRetentionMinutes: 0
        )

        try expect(
            settings.refreshIntervalSeconds == DisplaySettings.defaultRefreshIntervalSeconds,
            "unsupported refresh interval should fall back to default"
        )
        try expect(
            settings.maximumTaskCount == DisplaySettings.defaultMaximumTaskCount,
            "unsupported task count should fall back to default"
        )
        try expect(
            settings.justCompletedRetentionMinutes == DisplaySettings.defaultJustCompletedRetentionMinutes,
            "unsupported completed retention should fall back to default"
        )
    },
    TestCase(name: "display settings repository persists and reloads values") {
        let suiteName = "DisplaySettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = DisplaySettingsRepository(defaults: defaults)

        repository.save(DisplaySettings(
            refreshIntervalSeconds: 10,
            maximumTaskCount: 20,
            appLanguage: .english,
            justCompletedRetentionMinutes: 4,
            colorBlindSafeStatusIndicators: true
        ))
        let loaded = repository.load()

        try expect(loaded.refreshIntervalSeconds == 10, "refresh interval should persist")
        try expect(loaded.maximumTaskCount == 20, "maximum task count should persist")
        try expect(loaded.appLanguage == .english, "language should persist")
        try expect(loaded.justCompletedRetentionMinutes == 4, "completed retention should persist")
        try expect(
            loaded.colorBlindSafeStatusIndicators,
            "color-blind-safe status preference should persist"
        )
    },
    TestCase(name: "display settings repository defaults invalid language to system") {
        let suiteName = "DisplaySettingsTests.invalidLanguage.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unsupported", forKey: DisplayPreferenceKeys.appLanguage)

        let loaded = DisplaySettingsRepository(defaults: defaults).load()

        try expect(loaded.appLanguage == .system, "invalid language should fall back to system")
        try expect(
            loaded.justCompletedRetentionMinutes == DisplaySettings.defaultJustCompletedRetentionMinutes,
            "missing completed retention should fall back to one minute"
        )
    },
    TestCase(name: "display settings repository enables color blind safe indicators when preference is missing") {
        let suiteName = "DisplaySettingsTests.missingColorBlindPreference.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loaded = DisplaySettingsRepository(defaults: defaults).load()

        try expect(
            loaded.colorBlindSafeStatusIndicators,
            "missing color-blind-safe preference should use the enabled default"
        )
    },
    TestCase(name: "display settings repository preserves an explicit disabled color blind preference") {
        let suiteName = "DisplaySettingsTests.disabledColorBlindPreference.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: DisplayPreferenceKeys.colorBlindSafeStatusIndicators)

        let loaded = DisplaySettingsRepository(defaults: defaults).load()

        try expect(
            loaded.colorBlindSafeStatusIndicators == false,
            "an explicitly disabled color-blind-safe preference should remain disabled"
        )
    },
    TestCase(name: "display settings repository falls back for invalid completed retention") {
        let suiteName = "DisplaySettingsTests.invalidRetention.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(99, forKey: DisplayPreferenceKeys.justCompletedRetentionMinutes)

        let loaded = DisplaySettingsRepository(defaults: defaults).load()

        try expect(
            loaded.justCompletedRetentionMinutes == DisplaySettings.defaultJustCompletedRetentionMinutes,
            "invalid persisted completed retention should fall back to one minute"
        )
    }
]
