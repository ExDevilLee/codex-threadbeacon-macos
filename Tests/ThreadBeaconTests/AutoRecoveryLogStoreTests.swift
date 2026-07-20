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
        try expect(reloaded.first?.detail == "Codex CLI 已接受提示词（进程退出码 0）", "success detail should explain the boundary")
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
    }
]
