import ThreadBeaconCore

let archiveRestoreAvailabilityTests = [
    TestCase(name: "archive restore UI remains hidden while Codex App cannot restore sidebar access") {
        try expect(
            ArchiveRestoreAvailability.current.isEnabled == false,
            "archive restore must stay hidden until Codex App can reliably restore sidebar access"
        )
        try expect(
            ArchiveRestoreAvailability.current.blockedReason.contains("侧边栏"),
            "the availability contract should preserve the upstream limitation"
        )
    }
]
