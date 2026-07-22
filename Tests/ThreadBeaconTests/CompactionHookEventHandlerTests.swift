import Foundation
import ThreadBeaconCore

let compactionHookEventHandlerTests = [
    TestCase(name: "PreCompact writes and matching PostCompact clears marker") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 5_000)
        let handler = CompactionHookEventHandler(repository: fixture.repository, now: { now })

        try handler.handle(data: compactionHookJSON(
            event: "PreCompact",
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: "manual"
        ))
        let active = fixture.repository.activity(for: fixture.sessionID, now: now)
        try handler.handle(data: compactionHookJSON(
            event: "PostCompact",
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: "manual"
        ))

        try expect(active?.startedAt == now, "PreCompact receive time should become start time")
        try expect(
            fixture.repository.activity(for: fixture.sessionID, now: now) == nil,
            "matching PostCompact should clear marker"
        )
    },
    TestCase(name: "PostCompact with another turn preserves a newer marker") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 6_000)
        let handler = CompactionHookEventHandler(repository: fixture.repository, now: { now })
        try handler.handle(data: compactionHookJSON(
            event: "PreCompact",
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: "auto"
        ))

        try handler.handle(data: compactionHookJSON(
            event: "PostCompact",
            sessionID: fixture.sessionID,
            turnID: "019f8902-a543-7ab0-8833-81d2ce9f5785",
            trigger: "auto"
        ))

        try expect(
            fixture.repository.activity(for: fixture.sessionID, now: now) != nil,
            "old PostCompact must not clear another turn"
        )
    },
    TestCase(name: "compaction hook handler rejects unsupported or invalid input") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let handler = CompactionHookEventHandler(repository: fixture.repository)

        do {
            try handler.handle(data: compactionHookJSON(
                event: "Stop",
                sessionID: fixture.sessionID,
                turnID: fixture.turnID,
                trigger: "manual"
            ))
            throw TestFailure(description: "unsupported event should fail")
        } catch let error as CompactionHookEventError {
            try expect(error == .unsupportedEvent, "unsupported event should be classified")
        }

        do {
            try handler.handle(data: compactionHookJSON(
                event: "PreCompact",
                sessionID: "not-a-uuid",
                turnID: fixture.turnID,
                trigger: "manual"
            ))
            throw TestFailure(description: "invalid session should fail")
        } catch let error as CompactionHookEventError {
            try expect(error == .invalidIdentifier, "invalid identifier should be classified")
        }
    },
    TestCase(name: "compaction hook handler isolates concurrent sessions") {
        let fixture = try CompactionActivityFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 7_000)
        let secondSession = "019f8902-a543-7ab0-8833-81d2ce9f5790"
        let handler = CompactionHookEventHandler(repository: fixture.repository, now: { now })

        try handler.handle(data: compactionHookJSON(
            event: "PreCompact",
            sessionID: fixture.sessionID,
            turnID: fixture.turnID,
            trigger: "manual"
        ))
        try handler.handle(data: compactionHookJSON(
            event: "PreCompact",
            sessionID: secondSession,
            turnID: "019f8902-a543-7ab0-8833-81d2ce9f5791",
            trigger: "auto"
        ))

        try expect(fixture.repository.activity(for: fixture.sessionID, now: now) != nil, "first session remains")
        try expect(fixture.repository.activity(for: secondSession, now: now) != nil, "second session remains")
    }
]

private func compactionHookJSON(
    event: String,
    sessionID: String,
    turnID: String,
    trigger: String
) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "hook_event_name": event,
        "session_id": sessionID,
        "turn_id": turnID,
        "trigger": trigger,
        "cwd": "/private/path",
        "model": "private-model",
        "transcript_path": "/private/transcript.jsonl"
    ])
}
