import Foundation
import ThreadBeaconCore

let compactionActivityRepositoryTests = [
    TestCase(name: "compaction activity returns a fresh valid marker") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 1_000)
        let activity = CompactionActivity(
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: .manual,
            startedAt: now.addingTimeInterval(-5)
        )

        try fixture.repository.write(activity)
        let loaded = fixture.repository.activity(for: fixture.sessionID, now: now)

        try expect(loaded == activity, "fresh marker should be visible")
    },
    TestCase(name: "compaction activity expires after fifteen minutes") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_000)
        try fixture.repository.write(CompactionActivity(
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: .auto,
            startedAt: now.addingTimeInterval(-901)
        ))

        let loaded = fixture.repository.activity(for: fixture.sessionID, now: now)

        try expect(loaded == nil, "stale marker should be ignored")
        try expect(!FileManager.default.fileExists(atPath: fixture.markerURL.path), "stale marker should be removed")
    },
    TestCase(name: "compaction activity clears after newer terminal evidence") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 3_000)
        let startedAt = now.addingTimeInterval(-10)
        try fixture.repository.write(CompactionActivity(
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: .manual,
            startedAt: startedAt
        ))

        let completed = fixture.repository.activity(
            for: fixture.sessionID,
            completionEvidenceAt: startedAt.addingTimeInterval(1),
            now: now
        )

        try expect(completed == nil, "completion after start should clear activity")
    },
    TestCase(name: "compaction activity rejects future and malformed markers") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 4_000)
        try fixture.repository.write(CompactionActivity(
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: .manual,
            startedAt: now.addingTimeInterval(120)
        ))

        let future = fixture.repository.activity(for: fixture.sessionID, now: now)
        try Data("not-json".utf8).write(to: fixture.markerURL, options: .atomic)
        let malformed = fixture.repository.activity(for: fixture.sessionID, now: now)

        try expect(future == nil, "marker from the future should be ignored")
        try expect(malformed == nil, "malformed marker should be ignored")
    }
]

struct CompactionActivityFixture {
    let directoryURL: URL
    let repository: CompactionActivityRepository
    let sessionID = "019f8902-a543-7ab0-8833-81d2ce9f5783"
    let turnID = "019f8902-a543-7ab0-8833-81d2ce9f5784"

    var markerURL: URL {
        directoryURL.appendingPathComponent(sessionID).appendingPathExtension("json")
    }

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadBeaconCompactionActivityTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        repository = CompactionActivityRepository(directoryURL: directoryURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
