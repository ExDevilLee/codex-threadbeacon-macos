import ThreadBeaconCore
import Foundation

let displaySettingsTests = [
    TestCase(name: "display settings preserve supported values") {
        let settings = DisplaySettings(
            refreshIntervalSeconds: 5,
            maximumTaskCount: 12
        )

        try expect(settings.refreshIntervalSeconds == 5, "supported refresh interval should be retained")
        try expect(settings.maximumTaskCount == 12, "supported task count should be retained")
        try expect(settings.appLanguage == .system, "language should default to system")
    },
    TestCase(name: "display settings replace unsupported values with defaults") {
        let settings = DisplaySettings(
            refreshIntervalSeconds: 3,
            maximumTaskCount: 99
        )

        try expect(
            settings.refreshIntervalSeconds == DisplaySettings.defaultRefreshIntervalSeconds,
            "unsupported refresh interval should fall back to default"
        )
        try expect(
            settings.maximumTaskCount == DisplaySettings.defaultMaximumTaskCount,
            "unsupported task count should fall back to default"
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
            appLanguage: .english
        ))
        let loaded = repository.load()

        try expect(loaded.refreshIntervalSeconds == 10, "refresh interval should persist")
        try expect(loaded.maximumTaskCount == 20, "maximum task count should persist")
        try expect(loaded.appLanguage == .english, "language should persist")
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
    }
]
