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

        let sql = """
        SELECT id, title, rollout_path, COALESCE(updated_at_ms, updated_at * 1000)
        FROM threads
        WHERE archived = 0
          AND COALESCE(thread_source, '') <> 'subagent'
        ORDER BY recency_at_ms DESC, id DESC
        LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int(statement, 1, Int32(limit)) == SQLITE_OK else {
            throw SQLiteThreadRepositoryError.database(databaseMessage(database))
        }

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
                records.append(ThreadRecord(
                    id: String(cString: idText),
                    title: String(cString: titleText),
                    rolloutPath: String(cString: rolloutText),
                    updatedAt: Date(timeIntervalSince1970: Double(updatedAtMilliseconds) / 1_000)
                ))
            case SQLITE_DONE:
                return records
            default:
                throw SQLiteThreadRepositoryError.database(databaseMessage(database))
            }
        }
    }

    private func databaseMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else {
            return "未知 SQLite 错误"
        }
        return String(cString: message)
    }
}
