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
    TestCase(name: "log parser keeps exhausted reconnect attempt as warning before final error") {
        let records = [
            logRecord(
                second: 275,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-disconnect-warning}: stream disconnected - retrying sampling request (5/5 in 3s)..."
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .retrying, "5/5 alone should remain a warning")
        try expect(incident?.retryAttempt == 5, "warning should retain the final reconnect attempt")
        try expect(incident?.retryLimit == 5, "warning should retain the reconnect limit")
    },
    TestCase(name: "log parser turns exhausted reconnect followed by final disconnect into failure") {
        let records = [
            logRecord(
                second: 280,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-disconnect}: stream disconnected - retrying sampling request (5/5 in 3s)..."
            ),
            logRecord(
                second: 281,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-disconnect}: Turn error: stream disconnected before completion: error sending request for url (<redacted>)"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "final disconnect after 5/5 should become failure")
        try expect(incident?.kind == .streamDisconnected, "disconnect should retain its incident kind")
        try expect(incident?.httpStatusCode == nil, "disconnect should not invent an HTTP status")
        try expect(incident?.retryAttempt == 5, "disconnect should retain retry progress")
        try expect(incident?.retryLimit == 5, "disconnect should retain retry limit")
        try expect(
            incident?.occurredAt == Date(timeIntervalSince1970: 281),
            "final disconnect time should override retry time"
        )
    },
    TestCase(name: "log parser ignores final disconnect without exhausted reconnect") {
        let records = [
            logRecord(
                second: 290,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-disconnect-unmatched}: Turn error: stream disconnected before completion: error sending request for url (<redacted>)"
            )
        ]

        let incidents = LogEventParser().latestIncidents(from: records)

        try expect(incidents["thread-a"] == nil, "disconnect without 5/5 should not create an incident")
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
    TestCase(name: "log parser clears retry episode after new client target recovers") {
        let records = [
            logRecord(
                second: 350,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-new-client}: Request completed status=503 Service Unavailable"
            ),
            logRecord(
                second: 351,
                target: "codex_core::responses_retry",
                body: "turn{turn.id=turn-new-client}: stream disconnected - retrying sampling request (4/5 in 420ms)..."
            ),
            logRecord(
                second: 352,
                target: "codex_http_client::client",
                body: "turn{turn.id=turn-new-client}: Request completed status=200 OK"
            )
        ]

        let incidents = LogEventParser().latestIncidents(from: records)

        try expect(
            incidents["thread-a"] == nil,
            "a later success from the new client target should clear warning"
        )
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
    },
    TestCase(name: "log parser recognizes terminal 400 bad request") {
        let records = [
            logRecord(
                second: 500,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-bad-request}: Request completed status=400 Bad Request"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "completed 400 request should immediately become failure")
        try expect(incident?.kind == .badRequest, "400 should retain its incident kind")
        try expect(incident?.httpStatusCode == 400, "400 should retain its HTTP status")
    },
    TestCase(name: "log parser recognizes other terminal HTTP failures") {
        let records = [
            logRecord(
                second: 600,
                target: "codex_http_client::default_client",
                body: "turn{turn.id=turn-other-http}: Request completed status=500 Internal Server Error"
            ),
            logRecord(
                second: 601,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-other-http}: Turn error: unexpected status 500 Internal Server Error"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "other HTTP failures should become terminal failures")
        try expect(incident?.kind == .httpStatus(500), "unclassified HTTP status should be retained")
        try expect(incident?.httpStatusCode == 500, "other HTTP status should be retained")
    },
    TestCase(name: "log parser recognizes retry-limit error with colon status format") {
        let records = [
            logRecord(
                second: 700,
                target: "codex_core::session::turn",
                body: "turn{turn.id=turn-colon-status}: Turn error: exceeded retry limit, last status: 429 Too Many Requests, request id: redacted"
            )
        ]

        let incident = LogEventParser().latestIncidents(from: records)["thread-a"]

        try expect(incident?.phase == .failed, "retry-limit 429 should become failure")
        try expect(incident?.kind == .httpRateLimit, "retry-limit 429 should retain its incident kind")
        try expect(incident?.httpStatusCode == 429, "colon status format should retain HTTP status")
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
