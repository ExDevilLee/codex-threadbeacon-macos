import ThreadBeaconCore

let threadStatusTests = [
    TestCase(name: "status priority places actionable states first") {
        try expect(
            ThreadDisplayStatus.error.sortOrder < ThreadDisplayStatus.running.sortOrder,
            "error should sort before running"
        )
        try expect(
            ThreadDisplayStatus.needsAction.sortOrder < ThreadDisplayStatus.running.sortOrder,
            "needsAction should sort before running"
        )
        try expect(
            ThreadDisplayStatus.running.sortOrder < ThreadDisplayStatus.idle.sortOrder,
            "running should sort before idle"
        )
    }
]
