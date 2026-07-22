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
        try expect(records.first?.tokensUsed == 70_808_875, "repository should retain token total")
        try expect(records.first?.subagentCount == 3, "all direct child relationships should be counted")
        try expect(records.first?.model == "gpt-test-main", "repository should retain the main task model")
        try expect(records.first?.reasoningEffort == "xhigh", "repository should retain main reasoning effort")
    },
    TestCase(name: "repository respects requested limit") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL).loadRecent(limit: 1)

        try expect(records.map(\.id) == ["new-thread"], "limit should cap result count")
    },
    TestCase(name: "repository loads requested active primary threads by ID") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL)
            .loadByIDs(["new-thread", "archived-thread", "subagent-thread", "missing"])

        try expect(
            records.map(\.id) == ["new-thread"],
            "explicit lookup should exclude archived, subagent, and missing threads"
        )
    },
    TestCase(name: "repository loads archived primary favorites by ID") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL)
            .loadByIDsIncludingArchived(["new-thread", "archived-thread", "subagent-thread", "missing"])

        try expect(
            records.map(\.id) == ["archived-thread", "new-thread"],
            "favorite lookup should include archived primary tasks but exclude subagents and missing IDs"
        )
        try expect(records.first?.isArchived == true, "archived lifecycle state should be retained")
        try expect(records.last?.isArchived == false, "active lifecycle state should be retained")
    },
    TestCase(name: "repository falls back when spawn edges table is unavailable") {
        let databaseURL = try makeTemporaryThreadDatabase(includeSpawnEdges: false)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL).loadRecent(limit: 8)

        try expect(
            records.allSatisfy { $0.subagentCount == 0 },
            "missing relationship table should fall back to zero"
        )
    },
    TestCase(name: "repository loads direct subagents for requested parents") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let recordsByParent = try SQLiteThreadRepository(databaseURL: databaseURL)
            .loadDirectSubagents(parentIDs: ["new-thread"])
        let records = recordsByParent["new-thread"] ?? []

        try expect(
            records.map(\.id) == ["archived-child", "legacy-child", "subagent-thread"],
            "all direct children should load in recency order"
        )
        try expect(records[0].parentID == "new-thread", "parent identity should be retained")
        try expect(records[0].agentNickname == "archived-agent", "agent nickname should load")
        try expect(records[1].agentRole == "explorer", "agent role should load")
        try expect(records[2].model == "gpt-test", "model should load")
        try expect(records[2].reasoningEffort == "high", "reasoning effort should load")
    },
    TestCase(name: "repository loads only fresh subagent activity candidates") {
        let databaseURL = try makeTemporaryThreadDatabase()
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let recordsByParent = try SQLiteThreadRepository(databaseURL: databaseURL)
            .loadRecentSubagentCandidates(
                parentIDs: ["new-thread"],
                updatedAfter: Date(timeIntervalSince1970: 305)
            )

        try expect(
            recordsByParent["new-thread"]?.map(\.id) == ["archived-child", "legacy-child"],
            "only children at or after the activity cutoff should load"
        )
    },
    TestCase(name: "repository returns no activity candidates without spawn edges") {
        let databaseURL = try makeTemporaryThreadDatabase(includeSpawnEdges: false)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let records = try SQLiteThreadRepository(databaseURL: databaseURL)
            .loadRecentSubagentCandidates(
                parentIDs: ["new-thread"],
                updatedAfter: Date(timeIntervalSince1970: 0)
            )

        try expect(records.isEmpty, "missing relationship table should return no candidates")
    },
    TestCase(name: "repository skips activity query for empty parent set") {
        let missingDatabase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        let records = try SQLiteThreadRepository(databaseURL: missingDatabase)
            .loadRecentSubagentCandidates(
                parentIDs: [],
                updatedAfter: Date(timeIntervalSince1970: 0)
            )

        try expect(records.isEmpty, "empty parent set should not access the database")
    }
]

private func makeTemporaryThreadDatabase(includeSpawnEdges: Bool = true) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw TestFailure(description: "could not create temporary SQLite database")
    }
    defer { sqlite3_close(database) }

    let relationshipSQL = includeSpawnEdges ? """
    CREATE TABLE thread_spawn_edges (
        parent_thread_id TEXT NOT NULL,
        child_thread_id TEXT NOT NULL PRIMARY KEY,
        status TEXT NOT NULL
    );
    INSERT INTO thread_spawn_edges VALUES
        ('new-thread', 'subagent-thread', 'open'),
        ('new-thread', 'legacy-child', 'closed'),
        ('new-thread', 'archived-child', 'closed');
    """ : ""
    let sql = """
    CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        rollout_path TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        updated_at_ms INTEGER,
        recency_at_ms INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0,
        thread_source TEXT,
        tokens_used INTEGER NOT NULL DEFAULT 0,
        agent_nickname TEXT,
        agent_role TEXT,
        model TEXT,
        reasoning_effort TEXT
    );
    INSERT INTO threads VALUES
        ('older-thread', 'Older', '/tmp/older.jsonl', 100, 100000, 100000, 0, 'user', 1, NULL, NULL, NULL, NULL),
        ('new-thread', 'New', '/tmp/new.jsonl', 200, 200000, 300000, 0, 'user', 70808875, NULL, NULL, 'gpt-test-main', 'xhigh'),
        ('subagent-thread', 'Child', '/tmp/child.jsonl', 300, 300000, 500000, 0, 'subagent', 2, 'worker-agent', 'worker', 'gpt-test', 'high'),
        ('legacy-child', 'Legacy Child', '/tmp/legacy.jsonl', 310, 310000, 510000, 0, NULL, 4, 'legacy-agent', 'explorer', 'gpt-test', 'medium'),
        ('archived-child', 'Archived Child', '/tmp/archived-child.jsonl', 320, 320000, 520000, 1, NULL, 5, 'archived-agent', 'default', 'gpt-test', 'low'),
        ('archived-thread', 'Archived', '/tmp/archived.jsonl', 400, 400000, 400000, 1, 'user', 3, NULL, NULL, NULL, NULL);
    \(relationshipSQL)
    """
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw TestFailure(description: message)
    }
    return url
}
