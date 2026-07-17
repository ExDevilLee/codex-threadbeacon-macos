import Foundation

public enum CodexPaths {
    public static var stateDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }

    public static var sessionIndexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
    }

    public static var logsDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/logs_2.sqlite")
    }
}
