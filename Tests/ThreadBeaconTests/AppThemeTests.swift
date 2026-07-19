import ThreadBeaconCore

let appThemeTests = [
    TestCase(name: "app theme exposes system light and dark options") {
        try expect(
            AppTheme.allCases == [.system, .light, .dark],
            "theme options should preserve the Settings order"
        )
        try expect(AppTheme.defaultValue == .system, "theme should default to system")
    },
    TestCase(name: "invalid app theme falls back to system") {
        let theme = AppTheme(rawValue: "unsupported") ?? .defaultValue
        try expect(theme == .system, "invalid theme should fall back to system")
    }
]
