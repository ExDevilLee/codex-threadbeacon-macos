import ThreadBeaconCore

let tokenCountFormatterTests = [
    TestCase(name: "token counts use compact deterministic units") {
        try expect(TokenCountFormatter.string(for: 999) == "999", "small values should stay exact")
        try expect(TokenCountFormatter.string(for: 1_200) == "1.2K", "thousands should use K")
        try expect(TokenCountFormatter.string(for: 70_808_875) == "70.8M", "millions should use M")
    },
    TestCase(name: "token cache ratio uses one decimal percent") {
        try expect(TokenCountFormatter.percent(0.931432) == "93.1%", "ratio should use one decimal")
    }
]
