import CSQLite
import ThreadBeaconCore
import Foundation

let sqliteThreadRepositoryTests = [
    TestCase(name: "repository loads recent non archived threads with rollout paths") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL).loadRecent(limit: 8)

        try expect(records.map(\.id) == ["new-thread", "older-thread"], "records should use recency order")
        try expect(records.first?.title == "New", "repository should use the persisted thread title")
        try expect(records.first?.rolloutPath == "/tmp/new.jsonl", "rollout path should be retained")
    },
    TestCase(name: "repository respects requested limit") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL).loadRecent(limit: 1)

        try expect(records.map(\.id) == ["new-thread"], "limit should cap result count")
    }
]

private func makeTemporaryThreadDatabase() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw TestFailure(description: "could not create temporary SQLite database")
    }
    defer { sqlite3_close(database) }

    let sql = """
    CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        rollout_path TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        updated_at_ms INTEGER,
        recency_at_ms INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        thread_source TEXT
    );
    INSERT INTO threads VALUES
        ('older-thread', 'Older', '/tmp/older.jsonl', 100, 100000, 100000, 0, 'user'),
        ('new-thread', 'New', '/tmp/new.jsonl', 200, 200000, 300000, 0, 'user'),
        ('subagent-thread', 'Child', '/tmp/child.jsonl', 300, 300000, 500000, 0, 'subagent'),
        ('archived-thread', 'Archived', '/tmp/archived.jsonl', 400, 400000, 400000, 1, 'user');
    """
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw TestFailure(description: message)
    }
    return url
}
