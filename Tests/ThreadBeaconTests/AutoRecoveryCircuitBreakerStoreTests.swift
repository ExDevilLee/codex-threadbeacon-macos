import Foundation
import ThreadBeaconCore

let autoRecoveryCircuitBreakerStoreTests = [
    TestCase(name: "circuit breaker records isolated attempts by task and incident type") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let http400 = recoveryCircuitCandidate(threadID: "thread-a", type: .http400, episodeID: "episode-1")
        let http429 = recoveryCircuitCandidate(threadID: "thread-a", type: .http429, episodeID: "episode-2")
        let otherTask = recoveryCircuitCandidate(threadID: "thread-b", type: .http400, episodeID: "episode-3")
        let attemptAt = Date(timeIntervalSince1970: 100)

        let states = await MainActor.run { () -> [AutoRecoveryCircuitState] in
            let store = AutoRecoveryCircuitBreakerStore(fileURL: fileURL)
            _ = store.recordAttempt(candidate: http400, at: attemptAt)
            _ = store.recordAttempt(
                candidate: recoveryCircuitCandidate(
                    threadID: "thread-a",
                    type: .http400,
                    episodeID: "episode-4"
                ),
                at: attemptAt.addingTimeInterval(1)
            )
            _ = store.recordAttempt(candidate: http429, at: attemptAt)
            _ = store.recordAttempt(candidate: otherTask, at: attemptAt)
            return store.states
        }

        try expect(states.count == 3, "task and incident keys should remain isolated")
        try expect(
            states.first(where: { $0.threadID == "thread-a" && $0.incidentType == .http400 })?.attemptCount == 2,
            "the same task and incident should increment"
        )
    },
    TestCase(name: "circuit breaker persists attempts across app restarts") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let candidate = recoveryCircuitCandidate(threadID: "thread-a", type: .http503, episodeID: "episode-1")

        await MainActor.run {
            let store = AutoRecoveryCircuitBreakerStore(fileURL: fileURL)
            _ = store.recordAttempt(candidate: candidate, at: Date(timeIntervalSince1970: 100))
        }
        let reloaded = await MainActor.run {
            AutoRecoveryCircuitBreakerStore(fileURL: fileURL).state(for: candidate)
        }

        try expect(reloaded?.attemptCount == 1, "persisted attempts should survive recreation")
        try expect(reloaded?.lastEpisodeID == "episode-1", "the latest episode should persist")
    },
    TestCase(name: "new task completion clears every incident count for that task") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let attemptAt = Date(timeIntervalSince1970: 100)

        let remaining = await MainActor.run { () -> [AutoRecoveryCircuitState] in
            let store = AutoRecoveryCircuitBreakerStore(fileURL: fileURL)
            _ = store.recordAttempt(
                candidate: recoveryCircuitCandidate(threadID: "thread-a", type: .http400),
                at: attemptAt
            )
            _ = store.recordAttempt(
                candidate: recoveryCircuitCandidate(threadID: "thread-a", type: .http429),
                at: attemptAt
            )
            _ = store.recordAttempt(
                candidate: recoveryCircuitCandidate(threadID: "thread-b", type: .http400),
                at: attemptAt
            )
            store.observeCompletion(
                threadID: "thread-a",
                completedAt: attemptAt.addingTimeInterval(1)
            )
            return store.states
        }

        try expect(remaining.count == 1, "a new completion should clear all types for one task")
        try expect(remaining.first?.threadID == "thread-b", "another task should remain untouched")
    },
    TestCase(name: "old task completion cannot clear a newer recovery attempt") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let candidate = recoveryCircuitCandidate(threadID: "thread-a", type: .http400)
        let attemptAt = Date(timeIntervalSince1970: 100)

        let state = await MainActor.run { () -> AutoRecoveryCircuitState? in
            let store = AutoRecoveryCircuitBreakerStore(fileURL: fileURL)
            _ = store.recordAttempt(candidate: candidate, at: attemptAt)
            store.observeCompletion(threadID: "thread-a", completedAt: attemptAt)
            return store.state(for: candidate)
        }

        try expect(state?.attemptCount == 1, "equal or older completion evidence must not reset")
    },
    TestCase(name: "manual circuit reset removes only the selected task and incident") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let selected = recoveryCircuitCandidate(threadID: "thread-a", type: .http400)
        let preserved = recoveryCircuitCandidate(threadID: "thread-a", type: .http429)

        let remaining = await MainActor.run { () -> [AutoRecoveryCircuitState] in
            let store = AutoRecoveryCircuitBreakerStore(fileURL: fileURL)
            _ = store.recordAttempt(candidate: selected, at: Date(timeIntervalSince1970: 100))
            _ = store.recordAttempt(candidate: preserved, at: Date(timeIntervalSince1970: 100))
            store.reset(threadID: selected.threadID, incidentType: selected.incidentType)
            return store.states
        }

        try expect(remaining.count == 1, "one reset should remove only one state")
        try expect(remaining.first?.incidentType == .http429, "the other incident type should remain")
    },
    TestCase(name: "corrupt circuit breaker state fails open without crashing") {
        let fileURL = circuitBreakerTestURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("not-json".utf8).write(to: fileURL)

        let states = await MainActor.run {
            AutoRecoveryCircuitBreakerStore(fileURL: fileURL).states
        }

        try expect(states.isEmpty, "corrupt state should fall back to an empty in-memory state")
    }
]

private func circuitBreakerTestURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("threadbeacon-circuit-\(UUID().uuidString).json")
}

private func recoveryCircuitCandidate(
    threadID: String,
    type: AutoRecoveryIncidentType,
    episodeID: String = "episode"
) -> AutoRecoveryCandidate {
    AutoRecoveryCandidate(
        threadID: threadID,
        episodeID: episodeID,
        incidentType: type,
        incidentLabel: type.rawValue
    )
}
