import ThreadBeaconCore

let appLanguageTests = [
    TestCase(name: "explicit Chinese language resolves to Simplified Chinese") {
        let identifier = AppLanguage.simplifiedChinese.resolvedLocaleIdentifier(
            preferredLanguages: ["de-DE"]
        )

        try expect(identifier == "zh-Hans", "explicit Chinese should ignore the system language")
    },
    TestCase(name: "explicit English language resolves to English") {
        let identifier = AppLanguage.english.resolvedLocaleIdentifier(
            preferredLanguages: ["zh-Hans"]
        )

        try expect(identifier == "en", "explicit English should ignore the system language")
    },
    TestCase(name: "system language maps every Chinese variant to Simplified Chinese") {
        let identifier = AppLanguage.system.resolvedLocaleIdentifier(
            preferredLanguages: ["zh-Hant-HK"]
        )

        try expect(identifier == "zh-Hans", "Chinese system languages should use the Chinese UI")
    },
    TestCase(name: "system language keeps English") {
        let identifier = AppLanguage.system.resolvedLocaleIdentifier(
            preferredLanguages: ["en-GB"]
        )

        try expect(identifier == "en", "English system languages should use the English UI")
    },
    TestCase(name: "unsupported system language falls back to English") {
        let identifier = AppLanguage.system.resolvedLocaleIdentifier(
            preferredLanguages: ["ja-JP"]
        )

        try expect(identifier == "en", "unsupported system languages should fall back to English")
    },
    TestCase(name: "missing system language falls back to English") {
        let identifier = AppLanguage.system.resolvedLocaleIdentifier(preferredLanguages: [])

        try expect(identifier == "en", "missing system language should fall back to English")
    }
]
