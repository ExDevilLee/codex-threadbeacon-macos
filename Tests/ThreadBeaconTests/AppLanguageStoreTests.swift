import Foundation
import ThreadBeaconCore

let appLanguageStoreTests = [
    TestCase(name: "language store publishes an immediate language change") {
        let suiteName = "AppLanguageStoreTests.immediate.\(UUID().uuidString)"
        let result = await MainActor.run { () -> (String, AppLanguage, String)? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = AppLanguageStore(defaults: defaults)
            store.setLanguage(.simplifiedChinese)
            return (store.rawValue, store.language, store.locale.identifier)
        }
        guard let result else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }

        try expect(result.0 == AppLanguage.simplifiedChinese.rawValue,
                   "raw value should update in the same event")
        try expect(result.1 == .simplifiedChinese,
                   "semantic language should update in the same event")
        try expect(result.2 == AppLanguage.simplifiedChinese.rawValue,
                   "locale should update in the same event")
    },
    TestCase(name: "language store persists the selected language") {
        let suiteName = "AppLanguageStoreTests.persistence.\(UUID().uuidString)"
        let persistedValue = await MainActor.run { () -> String? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = AppLanguageStore(defaults: defaults)
            store.setLanguage(.english)
            return defaults.string(forKey: DisplayPreferenceKeys.appLanguage)
        }
        try expect(persistedValue == AppLanguage.english.rawValue,
                   "selected language should persist")
    },
    TestCase(name: "language store normalizes an invalid persisted value") {
        let suiteName = "AppLanguageStoreTests.invalid.\(UUID().uuidString)"
        let result = await MainActor.run { () -> (String, String?)? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("unsupported", forKey: DisplayPreferenceKeys.appLanguage)
            let store = AppLanguageStore(defaults: defaults)
            return (store.rawValue, defaults.string(forKey: DisplayPreferenceKeys.appLanguage))
        }
        guard let result else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        try expect(result.0 == AppLanguage.system.rawValue,
                   "invalid language should normalize to system")
        try expect(result.1 == AppLanguage.system.rawValue,
                   "normalized language should persist")
    }
]
