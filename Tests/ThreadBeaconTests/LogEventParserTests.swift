import Foundation
import ThreadBeaconCore

let logEventParserTests = [
    TestCase(name: "log parser turns exhausted 503 retries into failure") {
        let records = [
            logRecord(
                second: 100,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-a}: Request completed status=503 Service Unavailable"
            ),
            logRecord(
                second: 101,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-a}: stream disconnected - retrying sampling request (5/5 in 3.1s)..."
            ),
            logRecord(
                second: 102,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-a}: Turn error: unexpected status 503 Service Unavailable"
            ),
            logRecord(
                second: 103,
                target: "codex_http_client::transport",
                body: "turn{turn.id=turn-a}: status=429 Too Many Requests private request body"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "Turn error should make the episode final")
        try expect(incident?.httpStatusCode == 503, "HTTP status should be retained")
        try expect(incident?.retryAttempt == 5, "latest retry attempt should be retained")
        try expect(incident?.retryLimit == 5, "retry limit should be retained")
        try expect(incident?.episodeID == "turn-a", "turn ID should identify the episode")
        try expect(
            incident?.occurredAt == Date(timeIntervalSince1970: 102),
            "final failure time should override retry time"
        )
    },
    TestCase(name: "log parser exposes active 429 retry as warning") {
        let records = [
            logRecord(
                second: 200,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-b}: Request completed status=429 Too Many Requests"
            ),
            logRecord(
                second: 201,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-b}: stream disconnected - retrying sampling request (3/5 in 900ms)..."
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .retrying, "retry without Turn error should remain warning")
        try expect(incident?.httpStatusCode == 429, "429 status should be retained")
        try expect(incident?.retryAttempt == 3, "warning should expose retry progress")
    },
    TestCase(name: "log parser turns exhausted 429 retries into failure") {
        let records = [
            logRecord(
                second: 250,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-rate-limit}: Request completed status=429 Too Many Requests"
            ),
            logRecord(
                second: 251,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-rate-limit}: retrying sampling request (5/5 in 2s)..."
            ),
            logRecord(
                second: 252,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-rate-limit}: Turn error: unexpected status 429 Too Many Requests"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "terminal 429 should become failure")
        try expect(incident?.httpStatusCode == 429, "terminal 429 should retain its status")
        try expect(incident?.retryAttempt == 5, "terminal 429 should retain retry progress")
    },
    TestCase(name: "log parser clears retry episode after same turn recovers") {
        let records = [
            logRecord(
                second: 300,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-c}: Request completed status=503 Service Unavailable"
            ),
            logRecord(
                second: 301,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-c}: stream disconnected - retrying sampling request (2/5 in 420ms)..."
            ),
            logRecord(
                second: 302,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-c}: Request completed status=200 OK"
            )
        ]

        let incidents = LogEventParser().latestIncidents(from: records)

        try expect(incidents["thread-a"] == nil, "a later success in the same turn should clear warning")
    },
    TestCase(name: "log parser recognizes model capacity terminal failure") {
        let records = [
            logRecord(
                second: 400,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-capacity}: Turn error: Selected model is at capacity. Please try a different model."
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "model capacity Turn error should become failure")
        try expect(incident?.kind == .modelCapacity, "model capacity should retain its incident kind")
        try expect(incident?.httpStatusCode == nil, "capacity failure should not invent an HTTP status")
    }
]

private func logRecord(second: TimeInterval, target: String, body: String) -> LogEventRecord {
    LogEventRecord(
        threadID: "thread-a",
        occurredAt: Date(timeIntervalSince1970: second),
        target: target,
        body: body
    )
}
