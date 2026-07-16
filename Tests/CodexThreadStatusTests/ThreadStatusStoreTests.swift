import CodexThreadStatusCore
import Foundation

let threadStatusStoreTests = [
    TestCase(name: "store refresh publishes snapshots and timestamp") {
        let snapshot = ThreadSnapshot(
            id: "running",
            title: "Running",
            status: .running,
            statusChangedAt: Date(),
            updatedAt: Date(),
            latestEventAt: Date()
        )
        let store = await MainActor.run {
            ThreadStatusStore(load: { [snapshot] })
        }

        await store.refresh()
        let result = await MainActor.run {
            (store.snapshots, store.lastRefreshedAt, store.errorMessage)
        }

        try expect(result.0.map(\.status) == [.running], "refresh should publish loaded snapshots")
        try expect(result.1 != nil, "refresh should publish timestamp")
        try expect(result.2 == nil, "successful refresh should clear error")
    }
]
