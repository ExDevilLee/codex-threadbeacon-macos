import CodexThreadStatusCore
import Foundation

let sessionIndexTitleRepositoryTests = [
    TestCase(name: "session index keeps the latest renamed title for each thread") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let indexURL = directory.appendingPathComponent("session_index.jsonl")
        let contents = """
        {"id":"thread-a","thread_name":"Original title","updated_at":"2026-07-16T02:49:33Z"}
        {"id":"thread-b","thread_name":"Other task","updated_at":"2026-07-16T03:00:00Z"}
        {"id":"thread-a","thread_name":"Renamed sample task","updated_at":"2026-07-16T04:11:59Z"}
        """
        try contents.write(to: indexURL, atomically: true, encoding: .utf8)

        let titles = try SessionIndexTitleRepository(indexURL: indexURL).loadLatestTitles()

        try expect(titles["thread-a"] == "Renamed sample task", "latest rename should win")
        try expect(titles["thread-b"] == "Other task", "other thread names should remain available")
    }
]
