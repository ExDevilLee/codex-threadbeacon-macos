import Foundation
import ThreadBeaconCore

let autoRecoveryLogStoreTests = [
    TestCase(name: "auto recovery log persists attempt and success") {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbeacon-auto-recovery-\(UUID().uuidString).json")
        let occurredAt = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 110)

        let entryID = await MainActor.run {
            let store = AutoRecoveryLogStore(fileURL: fileURL, now: { occurredAt })
            return store.recordAttempt(
                threadID: "thread-id",
                episodeID: "turn-id",
                incident: "HTTP 400",
                prompt: "刚才中断了，请继续未完成的任务"
            )
        }
        await MainActor.run {
            let store = AutoRecoveryLogStore(fileURL: fileURL, now: { completedAt })
            store.recordSuccess(entryID)
        }
        let reloaded = await MainActor.run {
            AutoRecoveryLogStore(fileURL: fileURL).entries
        }

        try expect(reloaded.count == 1, "one log entry should persist")
        try expect(reloaded.first?.status == .succeeded, "success status should persist")
        try expect(
            reloaded.first?.detail == "Codex App 已确认恢复消息并启动新任务",
            "success detail should describe the visible Accessibility path"
        )
        try expect(reloaded.first?.threadID == "thread-id", "thread ID should persist for observation")
        try expect(reloaded.first?.prompt == "刚才中断了，请继续未完成的任务", "prompt should persist")
        try? FileManager.default.removeItem(at: fileURL)
    },
    TestCase(name: "auto recovery log keeps only the newest bounded entries") {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbeacon-auto-recovery-\(UUID().uuidString).json")
        let count = AutoRecoveryLogStore.maximumEntries + 5
        let entries = await MainActor.run {
            let store = AutoRecoveryLogStore(fileURL: fileURL)
            for index in 0..<count {
                _ = store.recordAttempt(
                    threadID: "thread-\(index)",
                    episodeID: "turn-\(index)",
                    incident: "HTTP 429",
                    prompt: "继续"
                )
            }
            return store.entries
        }

        try expect(entries.count == AutoRecoveryLogStore.maximumEntries, "log should be bounded")
        try? FileManager.default.removeItem(at: fileURL)
    },
    TestCase(name: "auto recovery log records skipped external recovery") {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbeacon-auto-recovery-\(UUID().uuidString).json")
        let store = await MainActor.run {
            let store = AutoRecoveryLogStore(fileURL: fileURL)
            _ = store.recordAttempt(
                threadID: "thread-id",
                episodeID: "turn-id",
                incident: "HTTP 400",
                prompt: "刚才中断了，请继续未完成的任务"
            )
            return store
        }
        await MainActor.run {
            if let entryID = store.entries.first?.id {
                store.recordSkipped(entryID)
            }
        }
        let reloaded = await MainActor.run { AutoRecoveryLogStore(fileURL: fileURL).entries }
        try expect(reloaded.first?.status == .skipped, "external recovery should be skipped")
        try expect(reloaded.first?.detail == "需要 macOS Accessibility 授权", "skip detail should explain the permission boundary")
        try? FileManager.default.removeItem(at: fileURL)
    },
    TestCase(name: "auto recovery log records an opened circuit distinctly") {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("threadbeacon-auto-recovery-\(UUID().uuidString).json")
        let entries = await MainActor.run { () -> [AutoRecoveryLogEntry] in
            let store = AutoRecoveryLogStore(fileURL: fileURL)
            store.recordCircuitOpen(
                threadID: "thread-id",
                episodeID: "episode-id",
                incident: "HTTP 429",
                prompt: "continue",
                attemptCount: 3,
                limit: 3
            )
            return store.entries
        }

        try expect(entries.first?.status == .circuitOpen, "circuit blocking should not look like a generic skip")
        try expect(
            entries.first?.detail == "连续自动恢复已达到 3/3 次，已停止发送",
            "the log should expose the configured limit"
        )
        try? FileManager.default.removeItem(at: fileURL)
    }
]
