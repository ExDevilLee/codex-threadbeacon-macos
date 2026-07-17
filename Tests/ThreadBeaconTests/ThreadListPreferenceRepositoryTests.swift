import Foundation
import ThreadBeaconCore

let threadListPreferenceRepositoryTests = [
    TestCase(name: "thread preferences persist list controls") {
        let suiteName = "ThreadBeaconTests.preferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = ThreadListPreferenceRepository(defaults: defaults)
        let preferences = ThreadListPreferences(
            pinnedThreadIDs: ["pinned"],
            favoriteThreadIDs: ["favorite"],
            showsFavoritesOnly: true,
            ignoredRules: [
                "ignored": IgnoredThreadRule(
                    threadID: "ignored",
                    ignoredAt: Date(timeIntervalSince1970: 123),
                    mode: .untilNextTurn
                )
            ]
        )

        repository.save(preferences)

        try expect(repository.load() == preferences, "saved preferences should round trip")
    },
    TestCase(name: "thread preferences migrate data saved before favorites") {
        let suiteName = "ThreadBeaconTests.preferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyJSON = #"{"pinnedThreadIDs":["legacy-pin"],"ignoredRules":{}}"#
        defaults.set(Data(legacyJSON.utf8), forKey: "threadListPreferences.v1")

        let preferences = ThreadListPreferenceRepository(defaults: defaults).load()

        try expect(preferences.pinnedThreadIDs == ["legacy-pin"], "legacy pins should survive migration")
        try expect(preferences.favoriteThreadIDs.isEmpty, "legacy data should start with no favorites")
        try expect(!preferences.showsFavoritesOnly, "legacy data should keep the full list visible")
    },
    TestCase(name: "thread preferences fail open when stored data is invalid") {
        let suiteName = "ThreadBeaconTests.preferences.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "threadListPreferences.v1")

        let preferences = ThreadListPreferenceRepository(defaults: defaults).load()

        try expect(preferences == .empty, "invalid data should not keep tasks hidden")
    }
]
