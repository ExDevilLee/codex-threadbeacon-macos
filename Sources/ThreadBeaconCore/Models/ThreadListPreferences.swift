import Foundation

public enum ThreadIgnoreMode: String, Codable, Equatable, Sendable {
    case untilNextTurn
}

public struct IgnoredThreadRule: Codable, Equatable, Sendable {
    public let threadID: String
    public let ignoredAt: Date
    public let mode: ThreadIgnoreMode

    public init(threadID: String, ignoredAt: Date, mode: ThreadIgnoreMode) {
        self.threadID = threadID
        self.ignoredAt = ignoredAt
        self.mode = mode
    }
}

public struct ThreadListPreferences: Codable, Equatable, Sendable {
    public var pinnedThreadIDs: Set<String>
    public var favoriteThreadIDs: Set<String>
    public var showsFavoritesOnly: Bool
    public var ignoredRules: [String: IgnoredThreadRule]

    public init(
        pinnedThreadIDs: Set<String> = [],
        favoriteThreadIDs: Set<String> = [],
        showsFavoritesOnly: Bool = false,
        ignoredRules: [String: IgnoredThreadRule] = [:]
    ) {
        self.pinnedThreadIDs = pinnedThreadIDs
        self.favoriteThreadIDs = favoriteThreadIDs
        self.showsFavoritesOnly = showsFavoritesOnly
        self.ignoredRules = ignoredRules
    }

    public static let empty = ThreadListPreferences()

    private enum CodingKeys: String, CodingKey {
        case pinnedThreadIDs
        case favoriteThreadIDs
        case showsFavoritesOnly
        case ignoredRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedThreadIDs = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedThreadIDs) ?? []
        favoriteThreadIDs = try container.decodeIfPresent(Set<String>.self, forKey: .favoriteThreadIDs) ?? []
        showsFavoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .showsFavoritesOnly) ?? false
        ignoredRules = try container.decodeIfPresent(
            [String: IgnoredThreadRule].self,
            forKey: .ignoredRules
        ) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pinnedThreadIDs, forKey: .pinnedThreadIDs)
        try container.encode(favoriteThreadIDs, forKey: .favoriteThreadIDs)
        try container.encode(showsFavoritesOnly, forKey: .showsFavoritesOnly)
        try container.encode(ignoredRules, forKey: .ignoredRules)
    }
}
