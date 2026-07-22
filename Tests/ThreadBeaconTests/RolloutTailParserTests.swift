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
    TestCase(name: "latest valid turn context exposes effective model metadata") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{"model":"gpt-old","effort":"low"}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"turn_context","payload":{"model":"gpt-current","effort":"xhigh"}}"#,
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"turn_context","payload":{"model":"","effort":"   "}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.model == "gpt-current", "latest non-empty model should be retained")
        try expect(result.reasoningEffort == "xhigh", "latest non-empty effort should be retained")
    },
    TestCase(name: "latest final produces just completed state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .justCompleted, "latest final should be just completed")
    },
    TestCase(name: "interrupted abort ends the active turn") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted","turn_id":"private-turn-id"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:02:00Z")
        let retainedFields = Mirror(reflecting: result).children.compactMap(\.label)

        try expect(result.status == .interrupted, "interrupted abort should end the active turn")
        try expect(result.statusChangedAt == expected, "abort timestamp should start the interrupted duration")
        try expect(result.interruptionEventAt == expected, "abort should expose marker cleanup evidence")
        try expect(!retainedFields.contains("reason"), "abort reason must not be retained")
        try expect(!retainedFields.contains("turnID"), "turn ID must not be retained")
    },
    TestCase(name: "new task start clears an older interrupted state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"event_msg","payload":{"type":"task_started"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .running, "a newer task start should restore running state")
    },
    TestCase(name: "task completion overrides an older interrupted state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"event_msg","payload":{"type":"task_complete"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .justCompleted, "a newer task completion should win by event time")
    },
    TestCase(name: "abort completed at uses the later structured timestamp") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted","completed_at":"2026-07-16T01:04:00Z"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:04:00Z")

        try expect(result.status == .interrupted, "valid completed_at should preserve interrupted state")
        try expect(result.statusChangedAt == expected, "later completed_at should define the boundary")
    },
    TestCase(name: "numeric abort completed at falls back to the event timestamp") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted","completed_at":1784710980,"started_at":1784710800}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:03:00Z")

        try expect(result.status == .interrupted, "numeric completed_at must not discard an interrupted abort")
        try expect(result.statusChangedAt == expected, "unsupported completed_at should fall back to the event timestamp")
    },
    TestCase(name: "malformed abort completed at falls back to the event timestamp") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted","completed_at":"not-a-date"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:03:00Z")

        try expect(result.status == .interrupted, "malformed optional completed_at must not discard an interrupted abort")
        try expect(result.statusChangedAt == expected, "malformed completed_at should fall back to the event timestamp")
    },
    TestCase(name: "abort events without interrupted reason are ignored") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#,
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"cancelled"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .running, "unsupported abort reasons must not end the task")
    },
    TestCase(name: "real final answer phase produces just completed state") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"turn_context","payload":{}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)

        try expect(result.status == .justCompleted, "final_answer should complete the turn")
    },
    TestCase(name: "task complete exposes latest completion event without message text") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"private"}}"#,
            #"{"timestamp":"2026-07-16T01:04:00Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"new private"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:04:00Z")
        let retainedFields = Mirror(reflecting: result).children.compactMap(\.label)

        try expect(result.completionEventAt == expected, "latest task_complete should identify the done event")
        try expect(!retainedFields.contains("lastAgentMessage"), "completion evidence must not retain message text")
    },
    TestCase(name: "task started exposes latest incident clearing boundary") {
        let lines = [
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:03:00Z","type":"event_msg","payload":{"type":"task_started"}}"#
        ]

        let result = RolloutTailParser().parse(lines: lines)
        let expected = ISO8601DateFormatter().date(from: "2026-07-16T01:03:00Z")

        try expect(
            result.latestTaskStartedAt == expected,
            "latest task_started should clear older service incidents"
        )
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
    },
    TestCase(name: "recovery checkpoint requires the expected prompt and a newer task start") {
        let parser = RolloutRecoveryCheckpointParser(
            expectedUserMessage: "fixed recovery prompt"
        )
        let baseline = parser.parse(lines: [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"fixed recovery prompt"}}"#
        ])
        let confirmed = parser.parse(lines: [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"fixed recovery prompt"}}"#,
            #"{"timestamp":"2026-07-16T01:01:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:01:01Z","type":"event_msg","payload":{"type":"user_message","message":"fixed recovery prompt\n"}}"#
        ])
        let unrelatedMessage = parser.parse(lines: [
            #"{"timestamp":"2026-07-16T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"fixed recovery prompt"}}"#,
            #"{"timestamp":"2026-07-16T01:02:00Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-07-16T01:02:01Z","type":"event_msg","payload":{"type":"user_message","message":"unrelated concurrent message"}}"#
        ])

        try expect(
            confirmed.confirmsNewTurn(after: baseline),
            "both recovery events advancing should confirm the new turn"
        )
        try expect(
            !unrelatedMessage.confirmsNewTurn(after: baseline),
            "an unrelated user message must not confirm recovery delivery"
        )
        try expect(
            !Mirror(reflecting: confirmed).children.compactMap(\.label).contains("message"),
            "the checkpoint must not retain message content"
        )
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
