import CodexThreadStatusCore
import Foundation

let rolloutTailParserTests = [
    TestCase(name: "rollout observation does not retain reasoning summary") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"Private reasoning summary"}]}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let retainedFields = Mirror(reflecting: result).children.compactMap(\.label)

        try expect(!retainedFields.contains("summary"), "reasoning summary must not be retained")
    },
    TestCase(name: "events after latest final produce running state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"Inspecting logs"}]}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .running, "latest turn should be running")
    },
    TestCase(name: "latest final produces just completed state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .justCompleted, "latest final should be just completed")
    },
    TestCase(name: "real final answer phase produces just completed state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .justCompleted, "final_answer should complete the turn")
    },
    TestCase(name: "malformed lines and reasoning alone are ignored") {
        let lines = [
            "not-json",
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"Useful summary"}]}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"   "}]}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .unknown, "reasoning alone should not imply running")
    },
    TestCase(name: "commentary advances latest event time") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:03:00Z")

        try expect(result.latestEventAt == expected, "commentary should keep running evidence fresh")
    },
    TestCase(name: "tail reader discards a truncated first line") {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        let prefix = String(repeating: "x", count: RolloutTailParser.maximumBytes + 32) + "\n"
        let final = #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}"#
        try (prefix + final + "\n").write(to: temporaryURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let result = try RolloutTailParser().parse(fileURL: temporaryURL)

        try expect(result.status == .justCompleted, "complete line after truncated prefix should parse")
    }
]
