import ThreadBeaconCore

let subagentAliasFormatterTests = [
    TestCase(name: "subagent alias is shown only when distinct from title") {
        try expect(
            SubagentAliasFormatter.displayAlias(nickname: " explorer ", title: "Review task") == "explorer",
            "a distinct nickname should be trimmed and displayed"
        )
        try expect(
            SubagentAliasFormatter.displayAlias(nickname: "Review task", title: "Review task") == nil,
            "a nickname matching the title should not be repeated"
        )
        try expect(
            SubagentAliasFormatter.displayAlias(nickname: "  ", title: "Review task") == nil,
            "a blank nickname should remain hidden"
        )
    }
]
