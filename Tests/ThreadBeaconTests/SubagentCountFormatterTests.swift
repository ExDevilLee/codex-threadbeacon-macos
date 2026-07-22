import ThreadBeaconCore

let subagentCountFormatterTests = [
    TestCase(name: "subagent count formatter hides zero total") {
        try expect(
            SubagentCountFormatter.label(activeCount: 0, totalCount: 0) == nil,
            "zero total should not reserve badge space"
        )
    },
    TestCase(name: "subagent count formatter exposes active and total counts") {
        let label = SubagentCountFormatter.label(activeCount: 2, totalCount: 27)

        try expect(label?.countText == "2/27", "badge should show active over total")
        try expect(label?.activeCount == 2, "label should retain active count")
        try expect(label?.totalCount == 27, "label should retain total count")
    },
    TestCase(name: "subagent count formatter keeps zero active count visible") {
        let label = SubagentCountFormatter.label(activeCount: 0, totalCount: 27)

        try expect(label?.countText == "0/27", "inactive history should remain visible")
    },
    TestCase(name: "subagent count formatter normalizes invalid counts") {
        let negative = SubagentCountFormatter.label(activeCount: -2, totalCount: 3)
        let excessive = SubagentCountFormatter.label(activeCount: 8, totalCount: 3)

        try expect(negative?.countText == "0/3", "negative active count should become zero")
        try expect(excessive?.countText == "3/3", "active count should not exceed total")
    }
]
