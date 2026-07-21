import ThreadBeaconCore

let statusIndicatorPresentationTests = [
    TestCase(name: "color blind safe status symbols remain stable") {
        let expected: [ThreadDisplayStatus: String] = [
            .error: "xmark.octagon.fill",
            .needsAction: "exclamationmark.square.fill",
            .warning: "exclamationmark.triangle.fill",
            .running: "play.circle.fill",
            .justCompleted: "checkmark.circle.fill",
            .idle: "minus.circle.fill",
            .unknown: "questionmark.circle.fill",
        ]

        for (status, symbolName) in expected {
            try expect(
                status.colorBlindSafeSymbolName == symbolName,
                "\(status.rawValue) should use \(symbolName)"
            )
        }
    },
    TestCase(name: "color blind safe status symbols are unique") {
        let symbols = ThreadDisplayStatus.allCases.map(\.colorBlindSafeSymbolName)

        try expect(
            Set(symbols).count == ThreadDisplayStatus.allCases.count,
            "every task status should have a distinct symbol"
        )
    },
]
