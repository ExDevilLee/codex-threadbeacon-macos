import ThreadBeaconCore

let subagentCountFormatterTests = [
    TestCase(name: "subagent count formatter hides zero") {
        try expect(
            SubagentCountFormatter.label(for: 0) == nil,
            "zero direct children should not reserve badge space"
        )
    },
    TestCase(name: "subagent count formatter exposes count and accessibility label") {
        let label = SubagentCountFormatter.label(for: 3)

        try expect(label?.countText == "3", "badge should retain the exact direct child count")
        try expect(label?.accessibilityLabel == "3 个 Subagent", "badge should explain the count")
    }
]
