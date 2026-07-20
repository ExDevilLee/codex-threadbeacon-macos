import CSQLite
import Foundation

public enum LogEventRepositoryError: Error, LocalizedError, Sendable {
    case database(String)
    case invalidRow

    public var errorDescription: String? {
        switch self {
        case let .database(message):
            return "读取 Codex 日志数据库失败：\(message)"
        case .invalidRow:
            return "Codex 日志数据库包含无法读取的记录"
        }
    }
}

public struct LogEventRepository: Sendable {
    public let databaseURL: URL
    private let parser: LogEventParser

    public init(databaseURL: URL, parser: LogEventParser = LogEventParser()) {
        self.databaseURL = databaseURL
        self.parser = parser
    }

    public func loadLatestIncidents(threadIDs: Set<String>) throws -> [String: ServiceIncident] {
        let threadIDs = threadIDs.sorted()
        guard !threadIDs.isEmpty else {
            return [:]
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map(databaseMessage) ?? "无法打开数据库"
            if let database {
                sqlite3_close(database)
            }
            throw LogEventRepositoryError.database(message)
        }
        defer { sqlite3_close(database) }

        let placeholders = Array(repeating: "?", count: threadIDs.count).joined(separator: ", ")
        let sql = """
        SELECT ts, ts_nanos, target, thread_id, feedback_log_body
        FROM logs
        WHERE thread_id IN (\(placeholders))
          AND feedback_log_body IS NOT NULL
          AND (
            (
              target = 'codex_http_client::default_client'
              AND feedback_log_body LIKE '%Request completed%'
              AND (
                feedback_log_body LIKE '%status=200 OK%'
                OR feedback_log_body LIKE '%status=429 Too Many Requests%'
                OR feedback_log_body LIKE '%status=503 Service Unavailable%'
              )
            )
            OR (
              target = 'codex_core::responses_retry'
              AND feedback_log_body LIKE '%retrying sampling request (%/%'
            )
            OR (
              target = 'codex_core::session::turn'
              AND feedback_log_body LIKE '%Turn error:%'
              AND (
                feedback_log_body LIKE '%status 429 Too Many Requests%'
                OR feedback_log_body LIKE '%status 503 Service Unavailable%'
                OR feedback_log_body LIKE '%Turn error: Selected model is at capacity. Please try a different model.%'
              )
            )
          )
        ORDER BY ts, ts_nanos, id
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LogEventRepositoryError.database(databaseMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, threadID) in threadIDs.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), threadID, -1, transient) == SQLITE_OK else {
                throw LogEventRepositoryError.database(databaseMessage(database))
            }
        }

        var records: [LogEventRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let targetText = sqlite3_column_text(statement, 2),
                      let threadIDText = sqlite3_column_text(statement, 3),
                      let bodyText = sqlite3_column_text(statement, 4) else {
                    throw LogEventRepositoryError.invalidRow
                }
                let seconds = sqlite3_column_int64(statement, 0)
                let nanoseconds = sqlite3_column_int64(statement, 1)
                records.append(LogEventRecord(
                    threadID: String(cString: threadIDText),
                    occurredAt: Date(
                        timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000
                    ),
                    target: String(cString: targetText),
                    body: String(cString: bodyText)
                ))
            case SQLITE_DONE:
                return parser.latestIncidents(from: records)
            default:
                throw LogEventRepositoryError.database(databaseMessage(database))
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
