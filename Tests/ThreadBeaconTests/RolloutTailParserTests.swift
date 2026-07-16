import ThreadBeaconCore
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
    },
    TestCase(name: "token events expose cumulative usage and current turn delta") {
        let lines = [
            tokenEvent(
                timestamp: "2026-07-16T01:00:00Z",
                input: 900,
                cached: 400,
                output: 100,
                reasoning: 30,
                total: 1_000
            ),
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            tokenEvent(
                timestamp: "2026-07-16T01:02:00Z",
                input: 1_350,
                cached: 650,
                output: 150,
                reasoning: 40,
                total: 1_500
            )
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.tokenUsage?.totalTokens == 1_500, "latest cumulative total should be retained")
        try expect(result.tokenUsage?.currentTurn?.inputTokens == 450, "turn input should use cumulative delta")
        try expect(result.tokenUsage?.currentTurn?.cachedInputTokens == 250, "turn cache should use cumulative delta")
        try expect(result.tokenUsage?.currentTurn?.outputTokens == 50, "turn output should use cumulative delta")
    },
    TestCase(name: "token delta is absent without a reliable baseline") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            tokenEvent(
                timestamp: "2026-07-16T01:02:00Z",
                input: 1_350,
                cached: 650,
                output: 150,
                reasoning: 40,
                total: 1_500
            )
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.tokenUsage?.totalTokens == 1_500, "cumulative total should still be available")
        try expect(result.tokenUsage?.currentTurn == nil, "missing baseline must not invent a turn total")
    },
    TestCase(name: "duplicate cumulative token events are not added together") {
        let lines = [
            tokenEvent(timestamp: "2026-07-16T01:00:00Z", input: 900, cached: 400,
                       output: 100, reasoning: 30, total: 1_000),
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            tokenEvent(timestamp: "2026-07-16T01:02:00Z", input: 1_350, cached: 650,
                       output: 150, reasoning: 40, total: 1_500),
            tokenEvent(timestamp: "2026-07-16T01:03:00Z", input: 1_350, cached: 650,
                       output: 150, reasoning: 40, total: 1_500)
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.tokenUsage?.totalTokens == 1_500, "duplicate totals must not be summed")
        try expect(result.tokenUsage?.currentTurn?.totalTokens == 500, "turn delta should remain cumulative")
    },
    TestCase(name: "backward cumulative values do not produce a turn delta") {
        let lines = [
            tokenEvent(timestamp: "2026-07-16T01:00:00Z", input: 900, cached: 400,
                       output: 100, reasoning: 30, total: 1_000),
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            tokenEvent(timestamp: "2026-07-16T01:02:00Z", input: 800, cached: 350,
                       output: 90, reasoning: 20, total: 890)
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.tokenUsage?.currentTurn == nil, "backward totals must be rejected")
    }
]

private func tokenEvent(
    timestamp: String,
    input: Int64,
    cached: Int64,
    output: Int64,
    reasoning: Int64,
    total: Int64
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)}}}}
    """
}
