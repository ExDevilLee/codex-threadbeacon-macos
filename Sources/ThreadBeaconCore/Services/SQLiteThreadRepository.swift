import CSQLite
import Foundation

public enum SQLiteThreadRepositoryError: Error, LocalizedError, Sendable {
    case invalidLimit
    case database(String)
    case invalidRow

    public var errorDescription: String? {
        switch self {
        case .invalidLimit:
            "线程数量必须大于 0"
        case let .database(message):
            "读取 Codex 数据库失败：\(message)"
        case .invalidRow:
            "Codex 数据库包含无法读取的线程记录"
        }
    }
}

public struct SQLiteThreadRepository: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func loadRecent(limit: Int) throws -> [ThreadRecord] {
        guard limit > 0, limit <= Int(Int32.max) else {
            throw SQLiteThreadRepositoryError.invalidLimit
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map(databaseMessage) ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteThreadRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        let hasSpawnEdges = try hasSpawnEdgesTable(in: database)
        let sql = hasSpawnEdges ? relationshipAwareSQL : legacySQL
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int(statement, 1, Int32(limit)) == SQLITE_OK else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }

        return try readThreadRecords(statement: statement, database: database)
    }

    public func loadByIDs(_ threadIDs: [String]) throws -> [ThreadRecord] {
        try loadByIDs(threadIDs, includingArchived: false)
    }

    public func loadByIDsIncludingArchived(_ threadIDs: [String]) throws -> [ThreadRecord] {
        try loadByIDs(threadIDs, includingArchived: true)
    }

    private func loadByIDs(
        _ threadIDs: [String],
        includingArchived: Bool
    ) throws -> [ThreadRecord] {
        let threadIDs = Array(Set(threadIDs)).sorted()
        guard !threadIDs.isEmpty else {
            return []
        }
        guard threadIDs.count <= Int(Int32.max) else {
            throw SQLiteThreadRepositoryError.invalidLimit
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map(databaseMessage) ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteThreadRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        let hasSpawnEdges = try hasSpawnEdgesTable(in: database)
        let placeholders = Array(repeating: "?", count: threadIDs.count).joined(separator: ", ")
        let sql = explicitThreadSQL(
            placeholders: placeholders,
            hasSpawnEdges: hasSpawnEdges,
            includingArchived: includingArchived
        )
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, threadID) in threadIDs.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), threadID, -1, transient) == SQLITE_OK else {
                throw SQLiteThreadRepositoryError.database(databaseMessage(database))
            }
        }

        return try readThreadRecords(statement: statement, database: database)
    }

    private func readThreadRecords(
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws -> [ThreadRecord] {
        var records: [ThreadRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard
                    let idText = sqlite3_column_text(statement, 0),
                    let titleText = sqlite3_column_text(statement, 1),
                    let rolloutText = sqlite3_column_text(statement, 2)
                else {
                    throw SQLiteThreadRepositoryError.invalidRow
                }
                let updatedAtMilliseconds = sqlite3_column_int64(statement, 3)
                let tokensUsed = sqlite3_column_int64(statement, 4)
                let subagentCountValue = sqlite3_column_int64(statement, 5)
                let isArchived = sqlite3_column_int(statement, 6) != 0
                guard
                    subagentCountValue >= 0,
                    let subagentCount = Int(exactly: subagentCountValue)
                else {
                    throw SQLiteThreadRepositoryError.invalidRow
                }
                records.append(ThreadRecord(
                    id: String(cString: idText),
                    title: String(cString: titleText),
                    rolloutPath: String(cString: rolloutText),
                    updatedAt: Date(timeIntervalSince1970: Double(updatedAtMilliseconds) / 1_000),
                    tokensUsed: tokensUsed,
                    subagentCount: subagentCount,
                    isArchived: isArchived
                ))
            case SQLITE_DONE:
                return records
            default:
                throw SQLiteThreadRepositoryError.database(databaseMessage(database))
            }
        }
    }

    public func loadDirectSubagents(parentIDs: [String]) throws -> [String: [SubagentRecord]] {
        let parentIDs = Array(Set(parentIDs)).sorted()
        guard !parentIDs.isEmpty else {
            return [:]
        }
        guard parentIDs.count <= Int(Int32.max) else {
            throw SQLiteThreadRepositoryError.invalidLimit
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map(databaseMessage) ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteThreadRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        guard try hasSpawnEdgesTable(in: database) else {
            return [:]
        }

        let placeholders = Array(repeating: "?", count: parentIDs.count).joined(separator: ", ")
        let sql = """
        SELECT edge.parent_thread_id,
               child.id,
               child.title,
               child.rollout_path,
               COALESCE(child.updated_at_ms, child.updated_at * 1000),
               child.tokens_used,
               child.agent_nickname,
               child.agent_role,
               child.model,
               child.reasoning_effort
        FROM thread_spawn_edges AS edge
        JOIN threads AS child ON child.id = edge.child_thread_id
        WHERE edge.parent_thread_id IN (\(placeholders))
        ORDER BY edge.parent_thread_id,
                 child.recency_at_ms DESC,
                 child.id DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, parentID) in parentIDs.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), parentID, -1, transient) == SQLITE_OK else {
                throw SQLiteThreadRepositoryError.database(databaseMessage(database))
            }
        }

        var recordsByParent: [String: [SubagentRecord]] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard
                    let parentIDText = sqlite3_column_text(statement, 0),
                    let idText = sqlite3_column_text(statement, 1),
                    let titleText = sqlite3_column_text(statement, 2),
                    let rolloutText = sqlite3_column_text(statement, 3)
                else {
                    throw SQLiteThreadRepositoryError.invalidRow
                }
                let parentID = String(cString: parentIDText)
                let record = SubagentRecord(
                    id: String(cString: idText),
                    parentID: parentID,
                    title: String(cString: titleText),
                    rolloutPath: String(cString: rolloutText),
                    updatedAt: Date(
                        timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1_000
                    ),
                    tokensUsed: sqlite3_column_int64(statement, 5),
                    agentNickname: optionalString(statement, column: 6),
                    agentRole: optionalString(statement, column: 7),
                    model: optionalString(statement, column: 8),
                    reasoningEffort: optionalString(statement, column: 9)
                )
                recordsByParent[parentID, default: []].append(record)
            case SQLITE_DONE:
                return recordsByParent
            default:
                throw SQLiteThreadRepositoryError.database(databaseMessage(database))
            }
        }
    }

    private var relationshipAwareSQL: String {
        """
        SELECT t.id, t.title, t.rollout_path,
               COALESCE(t.updated_at_ms, t.updated_at * 1000),
               t.tokens_used,
               COALESCE(children.child_count, 0),
               t.archived
        FROM threads AS t
        LEFT JOIN (
            SELECT parent_thread_id, COUNT(*) AS child_count
            FROM thread_spawn_edges
            GROUP BY parent_thread_id
        ) AS children ON children.parent_thread_id = t.id
        WHERE t.archived = 0
          AND COALESCE(t.thread_source, '') <> 'subagent'
          AND NOT EXISTS (
              SELECT 1
              FROM thread_spawn_edges AS edge
              WHERE edge.child_thread_id = t.id
          )
        ORDER BY t.recency_at_ms DESC, t.id DESC
        LIMIT ?
        """
    }

    private var legacySQL: String {
        """
        SELECT id, title, rollout_path,
               COALESCE(updated_at_ms, updated_at * 1000),
               tokens_used,
               0,
               archived
        FROM threads
        WHERE archived = 0
          AND COALESCE(thread_source, '') <> 'subagent'
        ORDER BY recency_at_ms DESC, id DESC
        LIMIT ?
        """
    }

    private func explicitThreadSQL(
        placeholders: String,
        hasSpawnEdges: Bool,
        includingArchived: Bool
    ) -> String {
        let archiveClause = includingArchived ? "" : "AND t.archived = 0"
        if hasSpawnEdges {
            return """
            SELECT t.id, t.title, t.rollout_path,
                   COALESCE(t.updated_at_ms, t.updated_at * 1000),
                   t.tokens_used,
                   COALESCE(children.child_count, 0),
                   t.archived
            FROM threads AS t
            LEFT JOIN (
                SELECT parent_thread_id, COUNT(*) AS child_count
                FROM thread_spawn_edges
                GROUP BY parent_thread_id
            ) AS children ON children.parent_thread_id = t.id
            WHERE t.id IN (\(placeholders))
              \(archiveClause)
              AND COALESCE(t.thread_source, '') <> 'subagent'
              AND NOT EXISTS (
                  SELECT 1
                  FROM thread_spawn_edges AS edge
                  WHERE edge.child_thread_id = t.id
              )
            ORDER BY t.recency_at_ms DESC, t.id DESC
            """
        }
        let legacyArchiveClause = includingArchived ? "" : "AND archived = 0"
        return """
        SELECT id, title, rollout_path,
               COALESCE(updated_at_ms, updated_at * 1000),
               tokens_used,
               0,
               archived
        FROM threads
        WHERE id IN (\(placeholders))
          \(legacyArchiveClause)
          AND COALESCE(thread_source, '') <> 'subagent'
        ORDER BY recency_at_ms DESC, id DESC
        """
    }

    private func hasSpawnEdgesTable(in database: OpaquePointer) throws -> Bool {
        let sql = """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table' AND name = 'thread_spawn_edges'
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
    }

    private func databaseMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "未知 SQLite 错误"
        }
        return String(cString: message)
    }

    private func optionalString(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        let value = String(cString: text)
        return value.isEmpty ? nil : value
    }
}
