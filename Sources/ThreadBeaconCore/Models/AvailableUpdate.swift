import Foundation

public struct GitHubRelease: Equatable, Sendable {
    public let tagName: String
    public let htmlURL: URL
    public let isDraft: Bool
    public let isPrerelease: Bool

    public init(tagName: String, htmlURL: URL, isDraft: Bool, isPrerelease: Bool) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: SemanticVersion
    public let releaseURL: URL
    public let isPrerelease: Bool

    public init(version: SemanticVersion, releaseURL: URL, isPrerelease: Bool) {
        self.version = version
        self.releaseURL = releaseURL
        self.isPrerelease = isPrerelease
    }
}
