import CSQLite
import Foundation
import ThreadBeaconCore

let logEventRepositoryTests = [
    TestCase(name: "log repository reads only requested thread incidents from allowed targets") {
        let databaseURL = try makeTemporaryLogDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let incidents = try LogEventRepository(databaseURL: databaseURL)
            .loadLatestIncidents(threadIDs: ["thread-a", "thread-b"])

        try expect(incidents.count == 2, "only requested threads should be returned")
        try expect(incidents["thread-a"]?.phase == .failed, "503 Turn error should be returned")
        try expect(incidents["thread-a"]?.httpStatusCode == 503, "503 should survive SQLite read")
        try expect(incidents["thread-b"]?.phase == .retrying, "429 retry should be returned")
        try expect(incidents["thread-b"]?.httpStatusCode == 429, "429 should survive SQLite read")
        try expect(incidents["thread-c"] == nil, "unrequested thread must stay excluded")
    }
]

private func makeTemporaryLogDatabase() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw TestFailure(description: "could not create temporary log database")
    }
    defer { sqlite3_close(database) }

    let sql = """
    CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        ts_nanos INTEGER NOT NULL,
        level TEXT NOT NULL,
        target TEXT NOT NULL,
        feedback_log_body TEXT,
        module_path TEXT,
        file TEXT,
        line INTEGER,
        thread_id TEXT,
        process_uuid TEXT,
        estimated_bytes INTEGER NOT NULL DEFAULT 0
    );
    INSERT INTO logs (ts, ts_nanos, level, target, feedback_log_body, thread_id) VALUES
        (100, 0, 'DEBUG', 'codex_http_client::default_client',
         'turn{turn.id=turn-a}: Request completed status=503 Service Unavailable', 'thread-a'),
        (101, 0, 'INFO', 'codex_core::responses_retry',
         'turn{turn.id=turn-a}: retrying sampling request (5/5 in 3s)...', 'thread-a'),
        (102, 0, 'INFO', 'codex_core::session::turn',
         'turn{turn.id=turn-a}: Turn error: unexpected status 503 Service Unavailable', 'thread-a'),
        (103, 0, 'TRACE', 'codex_http_client::transport',
         'turn{turn.id=turn-a}: status=429 Too Many Requests private body', 'thread-a'),
        (200, 0, 'DEBUG', 'codex_http_client::default_client',
         'turn{turn.id=turn-b}: Request completed status=429 Too Many Requests', 'thread-b'),
        (201, 0, 'INFO', 'codex_core::responses_retry',
         'turn{turn.id=turn-b}: retrying sampling request (2/5 in 500ms)...', 'thread-b'),
        (300, 0, 'INFO', 'codex_core::session::turn',
         'turn{turn.id=turn-c}: Turn error: unexpected status 503 Service Unavailable', 'thread-c');
    """
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw TestFailure(description: message)
    }
    return url
}
