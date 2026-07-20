import Foundation

public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    private enum Identifier: Equatable, Hashable, Sendable {
        case numeric(Int)
        case text(String)
    }

    public let major: Int
    public let minor: Int
    public let patch: Int
    private let prerelease: [Identifier]

    public init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }

        let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard !buildParts.contains(where: { $0.isEmpty }) else { return nil }
        if buildParts.count == 2 {
            let buildIdentifiers = buildParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !buildIdentifiers.isEmpty,
                  buildIdentifiers.allSatisfy({ Self.hasValidIdentifierCharacters(String($0)) }) else {
                return nil
            }
        }

        let coreAndPrerelease = buildParts[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard coreAndPrerelease.count <= 2, !coreAndPrerelease.contains(where: { $0.isEmpty }) else { return nil }

        let core = coreAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.parseNumeric(core[0]),
              let minor = Self.parseNumeric(core[1]),
              let patch = Self.parseNumeric(core[2]) else { return nil }

        let prereleaseIdentifiers: [Identifier]
        if coreAndPrerelease.count == 2 {
            let rawIdentifiers = coreAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !rawIdentifiers.isEmpty, !rawIdentifiers.contains(where: { $0.isEmpty }) else { return nil }
            do {
                prereleaseIdentifiers = try rawIdentifiers.map(Self.parseIdentifier)
            } catch {
                return nil
            }
        } else {
            prereleaseIdentifiers = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prereleaseIdentifiers
    }

    public var description: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            value += "-" + prerelease.map(Self.identifierDescription).joined(separator: ".")
        }
        return value
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let coreComparison = [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes(
            [rhs.major, rhs.minor, rhs.patch]
        )
        if lhs.major != rhs.major || lhs.minor != rhs.minor || lhs.patch != rhs.patch {
            return coreComparison
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            switch (left, right) {
            case let (.numeric(left), .numeric(right)):
                return left < right
            case (.numeric, .text):
                return true
            case (.text, .numeric):
                return false
            case let (.text(left), .text(right)):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func parseNumeric<S: StringProtocol>(_ value: S) -> Int? {
        let string = String(value)
        guard !string.isEmpty,
              (string == "0" || !string.hasPrefix("0")),
              string.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(string)
    }

    private static func parseIdentifier<S: StringProtocol>(_ value: S) throws -> Identifier {
        let string = String(value)
        guard hasValidIdentifierCharacters(string) else {
            throw ParseError.invalidIdentifier
        }
        if let number = parseNumeric(string) {
            return .numeric(number)
        }
        guard !string.isEmpty, !string.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ParseError.invalidIdentifier
        }
        return .text(string)
    }

    private static func identifierDescription(_ identifier: Identifier) -> String {
        switch identifier {
        case let .numeric(value): return String(value)
        case let .text(value): return value
        }
    }

    private static func hasValidIdentifierCharacters(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    private enum ParseError: Error { case invalidIdentifier }
}
