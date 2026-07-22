import ThreadBeaconCore

let subagentAliasFormatterTests = [
    TestCase(name: "subagent task path becomes the preferred semantic label") {
        try expect(
            SubagentAliasFormatter.displayAlias(
                agentPath: "/root/fix_external_sync",
                nickname: "Lagrange",
                title: "Review workspace"
            ) == "Fix external sync",
            "agent task name should be humanized and preferred over the random nickname"
        )
        try expect(
            SubagentAliasFormatter.displayAlias(
                agentPath: nil,
                nickname: " explorer ",
                title: "Review task"
            ) == "explorer",
            "older records without an agent path should fall back to nickname"
        )
    },
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
