import Foundation

public enum SoundNotificationCategory: String, Equatable, Sendable {
    case done
    case attention
    case warning
    case failure
    case interrupted
}

public enum RefreshNotificationPolicy: Equatable, Sendable {
    case baseline
    case notify
}

public struct SoundNotificationEvent: Equatable, Sendable {
    public let id: String
    public let threadID: String
    public let category: SoundNotificationCategory

    public init(id: String, threadID: String, category: SoundNotificationCategory) {
        self.id = id
        self.threadID = threadID
        self.category = category
    }
}

public struct SoundNotificationTracker: Sendable {
    public private(set) var seenEventIDs: [String]
    private let maximumHistoryCount: Int

    public init(initialSeenEventIDs: [String] = [], maximumHistoryCount: Int = 256) {
        self.maximumHistoryCount = max(1, maximumHistoryCount)
        self.seenEventIDs = Array(initialSeenEventIDs.suffix(self.maximumHistoryCount))
    }

    public mutating func observe(
        _ snapshots: [ThreadSnapshot],
        policy: RefreshNotificationPolicy
    ) -> [SoundNotificationEvent] {
        let seen = Set(seenEventIDs)
        let candidates = snapshots.compactMap { snapshot -> SoundNotificationEvent? in
            if let incident = snapshot.serviceIncident {
                return SoundNotificationEvent(
                    id: "warning:\(snapshot.id):\(incident.episodeID)",
                    threadID: snapshot.id,
                    category: .warning
                )
            }
            guard let completedAt = snapshot.completionEventAt else { return nil }
            let milliseconds = Int64((completedAt.timeIntervalSince1970 * 1_000).rounded())
            return SoundNotificationEvent(
                id: "done:\(snapshot.id):\(milliseconds)",
                threadID: snapshot.id,
                category: .done
            )
        }
        let newEvents = candidates.filter { !seen.contains($0.id) }
        seenEventIDs.append(contentsOf: newEvents.map(\.id))

        var uniqueIDs: [String] = []
        var uniqueSet = Set<String>()
        for id in seenEventIDs where uniqueSet.insert(id).inserted {
            uniqueIDs.append(id)
        }
        seenEventIDs = Array(uniqueIDs.suffix(maximumHistoryCount))

        guard policy == .notify, let first = newEvents.first else { return [] }
        return [first]
    }
}
