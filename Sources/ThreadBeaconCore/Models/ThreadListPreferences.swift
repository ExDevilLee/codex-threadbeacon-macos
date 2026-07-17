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
    public var ignoredRules: [String: IgnoredThreadRule]

    public init(
        pinnedThreadIDs: Set<String> = [],
        ignoredRules: [String: IgnoredThreadRule] = [:]
    ) {
        self.pinnedThreadIDs = pinnedThreadIDs
        self.ignoredRules = ignoredRules
    }

    public static let empty = ThreadListPreferences()
}
