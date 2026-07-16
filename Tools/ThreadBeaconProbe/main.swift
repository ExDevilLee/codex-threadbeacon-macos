import ThreadBeaconCore
import Foundation

@main
enum ThreadBeaconProbe {
    static func main() async throws {
        let repository = SQLiteThreadRepository(databaseURL: CodexPaths.stateDatabaseURL)
        let loader = ThreadStatusLoader(repository: repository)
        let snapshots = try await loader.load(limit: 8)
        let grouped = Dictionary(grouping: snapshots, by: \.status)

        print("threads=\(snapshots.count)")
        for status in ThreadDisplayStatus.allCases {
            print("status.\(status.rawValue)=\(grouped[status]?.count ?? 0)")
        }
    }
}
