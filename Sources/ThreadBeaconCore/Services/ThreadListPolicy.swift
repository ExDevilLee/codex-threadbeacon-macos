import Foundation

public struct ThreadListResult: Equatable, Sendable {
    public let visibleSnapshots: [ThreadSnapshot]
    public let ignoredSnapshots: [ThreadSnapshot]
    public let preferences: ThreadListPreferences

    public init(
        visibleSnapshots: [ThreadSnapshot],
        ignoredSnapshots: [ThreadSnapshot],
        preferences: ThreadListPreferences
    ) {
        self.visibleSnapshots = visibleSnapshots
        self.ignoredSnapshots = ignoredSnapshots
        self.preferences = preferences
    }
}

public enum ThreadListPolicy {
    public static func evaluate(
        candidates: [ThreadSnapshot],
        preferences: ThreadListPreferences,
        limit: Int
    ) -> ThreadListResult {
        var preferences = preferences

        for snapshot in candidates {
            guard let rule = preferences.ignoredRules[snapshot.id],
                  rule.mode == .untilNextTurn,
                  let taskStartedAt = snapshot.latestTaskStartedAt,
                  taskStartedAt > rule.ignoredAt else {
                continue
            }
            preferences.ignoredRules.removeValue(forKey: snapshot.id)
        }

        let ignoredIDs = Set(preferences.ignoredRules.keys)
        let ignoredSnapshots = candidates
            .filter { ignoredIDs.contains($0.id) }
            .sorted { precedes($0, $1, pinnedThreadIDs: preferences.pinnedThreadIDs) }
        let displayCandidates = preferences.showsFavoritesOnly
            ? candidates.filter { preferences.favoriteThreadIDs.contains($0.id) }
            : candidates
        let visibleSnapshots = displayCandidates
            .filter { !ignoredIDs.contains($0.id) }
            .sorted { precedes($0, $1, pinnedThreadIDs: preferences.pinnedThreadIDs) }
            .prefix(max(0, limit))

        return ThreadListResult(
            visibleSnapshots: Array(visibleSnapshots),
            ignoredSnapshots: ignoredSnapshots,
            preferences: preferences
        )
    }

    private static func precedes(
        _ lhs: ThreadSnapshot,
        _ rhs: ThreadSnapshot,
        pinnedThreadIDs: Set<String>
    ) -> Bool {
        if lhs.status.sortOrder != rhs.status.sortOrder {
            return lhs.status.sortOrder < rhs.status.sortOrder
        }
        let lhsPinned = pinnedThreadIDs.contains(lhs.id)
        let rhsPinned = pinnedThreadIDs.contains(rhs.id)
        if lhsPinned != rhsPinned {
            return lhsPinned
        }
        let lhsEvent = lhs.latestEventAt ?? .distantPast
        let rhsEvent = rhs.latestEventAt ?? .distantPast
        if lhsEvent != rhsEvent {
            return lhsEvent > rhsEvent
        }
        return lhs.id < rhs.id
    }
}
