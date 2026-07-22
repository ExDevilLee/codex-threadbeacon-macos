import Foundation
import ThreadBeaconCore

let compactionHistoryRepositoryTests = [
    TestCase(name: "compaction history deduplicates paired events") {
        let fixture = try CompactionHistoryFixture(lines: [
            #"{"timestamp":"2026-07-22T01:00:00.000Z","type":"compacted","payload":{"message":"private"}}"#,
            #"{"timestamp":"2026-07-22T01:00:00.010Z","type":"event_msg","payload":{"type":"context_compacted"}}"#,
            #"{"timestamp":"2026-07-22T02:00:00.000Z","type":"compacted","payload":{"message":"private"}}"#,
            #"{"timestamp":"2026-07-22T02:00:00.015Z","type":"event_msg","payload":{"type":"context_compacted"}}"#
        ])
        defer { fixture.remove() }

        let history = try CompactionHistoryRepository().history(for: fixture.url)

        try expect(history.completionCount == 2, "paired compact events should count once")
        try expect(
            history.lastCompletedAt == compactionTestDate("2026-07-22T02:00:00.015Z"),
            "latest paired event should define completion time"
        )
    },
    TestCase(name: "compaction history supports single event formats and malformed lines") {
        let fixture = try CompactionHistoryFixture(lines: [
            "not-json",
            #"{"timestamp":"2026-07-22T01:00:00Z","type":"compacted","payload":{"message":"private"}}"#,
            #"{"timestamp":"2026-07-22T02:00:00Z","type":"event_msg","payload":{"type":"context_compacted"}}"#,
            #"{"timestamp":"invalid","type":"compacted"}"#
        ])
        defer { fixture.remove() }

        let history = try CompactionHistoryRepository().history(for: fixture.url)

        try expect(history.completionCount == 2, "unpaired old and new event formats should both count")
        try expect(
            history.lastCompletedAt == compactionTestDate("2026-07-22T02:00:00Z"),
            "malformed lines must not replace valid completion time"
        )
    },
    TestCase(name: "compaction history reads only appended lines after first scan") {
        let fixture = try CompactionHistoryFixture(lines: [
            #"{"timestamp":"2026-07-22T01:00:00Z","type":"compacted"}"#
        ])
        defer { fixture.remove() }
        let repository = CompactionHistoryRepository()

        let initial = try repository.history(for: fixture.url)
        try fixture.append(lines: [
            #"{"timestamp":"2026-07-22T02:00:00Z","type":"compacted"}"#,
            #"{"timestamp":"2026-07-22T02:00:00.010Z","type":"event_msg","payload":{"type":"context_compacted"}}"#
        ])
        let updated = try repository.history(for: fixture.url)

        try expect(initial.completionCount == 1, "initial scan should count existing event")
        try expect(updated.completionCount == 2, "incremental scan should add one paired completion")
    },
    TestCase(name: "compaction history resets when rollout is truncated") {
        let fixture = try CompactionHistoryFixture(lines: [
            #"{"timestamp":"2026-07-22T01:00:00Z","type":"compacted"}"#,
            #"{"timestamp":"2026-07-22T02:00:00Z","type":"compacted"}"#
        ])
        defer { fixture.remove() }
        let repository = CompactionHistoryRepository()

        let initial = try repository.history(for: fixture.url)
        try fixture.replace(lines: [
            #"{"timestamp":"2026-07-22T03:00:00Z","type":"event_msg","payload":{"type":"context_compacted"}}"#
        ])
        let replaced = try repository.history(for: fixture.url)

        try expect(initial.completionCount == 2, "initial scan should count both completions")
        try expect(replaced.completionCount == 1, "truncated rollout should rebuild history")
        try expect(
            replaced.lastCompletedAt == compactionTestDate("2026-07-22T03:00:00Z"),
            "rebuilt history should use replacement content"
        )
    },
    TestCase(name: "compaction history retains an incomplete appended line") {
        let fixture = try CompactionHistoryFixture(lines: [])
        defer { fixture.remove() }
        let repository = CompactionHistoryRepository()

        try fixture.append(raw: #"{"timestamp":"2026-07-22T04:00:00Z","type":"comp"#)
        let incomplete = try repository.history(for: fixture.url)
        try fixture.append(raw: "acted" + #""}"# + "\n")
        let completed = try repository.history(for: fixture.url)

        try expect(incomplete.completionCount == 0, "partial JSON must wait for its newline")
        try expect(completed.completionCount == 1, "completed partial JSON should be parsed once")
    }
]

private struct CompactionHistoryFixture {
    let url: URL

    init(lines: [String]) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadBeaconCompactionHistoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try replace(lines: lines)
    }

    func append(lines: [String]) throws {
        try append(raw: lines.joined(separator: "\n") + "\n")
    }

    func append(raw: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(raw.utf8))
    }

    func replace(lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

private func compactionTestDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
