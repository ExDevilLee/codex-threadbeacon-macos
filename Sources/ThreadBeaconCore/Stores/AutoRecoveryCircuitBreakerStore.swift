import Combine
import Foundation

@MainActor
public final class AutoRecoveryCircuitBreakerStore: ObservableObject {
    @Published public private(set) var states: [AutoRecoveryCircuitState] = []

    private let fileURL: URL
    private var statesByID: [String: AutoRecoveryCircuitState] = [:]

    public init(fileURL: URL = AutoRecoveryCircuitBreakerStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    public func state(for candidate: AutoRecoveryCandidate) -> AutoRecoveryCircuitState? {
        state(threadID: candidate.threadID, incidentType: candidate.incidentType)
    }

    public func state(
        threadID: String,
        incidentType: AutoRecoveryIncidentType
    ) -> AutoRecoveryCircuitState? {
        statesByID[AutoRecoveryCircuitState.id(
            threadID: threadID,
            incidentType: incidentType
        )]
    }

    @discardableResult
    public func recordAttempt(
        candidate: AutoRecoveryCandidate,
        at attemptedAt: Date = Date()
    ) -> AutoRecoveryCircuitState {
        let id = AutoRecoveryCircuitState.id(
            threadID: candidate.threadID,
            incidentType: candidate.incidentType
        )
        if let existing = statesByID[id], existing.lastEpisodeID == candidate.episodeID {
            return existing
        }
        var state = statesByID[id] ?? AutoRecoveryCircuitState(
            threadID: candidate.threadID,
            incidentType: candidate.incidentType,
            attemptCount: 1,
            lastEpisodeID: candidate.episodeID,
            lastAttemptAt: attemptedAt
        )
        if statesByID[id] != nil {
            state.attemptCount += 1
            state.lastEpisodeID = candidate.episodeID
            state.lastAttemptAt = attemptedAt
        }
        statesByID[id] = state
        publishAndPersist()
        return state
    }

    public func observeCompletion(threadID: String, completedAt: Date) {
        let matchingIDs = statesByID.values.compactMap { state in
            state.threadID == threadID && completedAt > state.lastAttemptAt
                ? state.id
                : nil
        }
        guard !matchingIDs.isEmpty else { return }
        matchingIDs.forEach { statesByID.removeValue(forKey: $0) }
        publishAndPersist()
    }

    public func reset(threadID: String, incidentType: AutoRecoveryIncidentType) {
        let id = AutoRecoveryCircuitState.id(
            threadID: threadID,
            incidentType: incidentType
        )
        guard statesByID.removeValue(forKey: id) != nil else { return }
        publishAndPersist()
    }

    public static var defaultFileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ThreadBeacon", isDirectory: true)
        return directory.appendingPathComponent("auto-recovery-circuit-breaker.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AutoRecoveryCircuitState].self, from: data) else {
            return
        }
        statesByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        publish()
    }

    private func publishAndPersist() {
        publish()
        guard let data = try? JSONEncoder().encode(states) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func publish() {
        states = statesByID.values.sorted {
            if $0.lastAttemptAt != $1.lastAttemptAt {
                return $0.lastAttemptAt > $1.lastAttemptAt
            }
            return $0.id < $1.id
        }
    }
}
