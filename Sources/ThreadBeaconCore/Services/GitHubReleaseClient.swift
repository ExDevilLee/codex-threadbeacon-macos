import Foundation

public enum GitHubReleaseClientError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case decodeFailed
}

public struct GitHubReleaseClient: Sendable {
    private struct ReleasePayload: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    public static let defaultEndpoint = URL(string:
        "https://api.github.com/repos/ExDevilLee/codex-threadbeacon-macos/releases?per_page=20"
    )!

    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = Self.defaultEndpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    public func check(currentVersion: SemanticVersion) async throws -> AvailableUpdate? {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ThreadBeacon/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubReleaseClientError.httpStatus(httpResponse.statusCode)
        }

        let payload: [ReleasePayload]
        do {
            payload = try JSONDecoder().decode([ReleasePayload].self, from: data)
        } catch {
            throw GitHubReleaseClientError.decodeFailed
        }

        let releases = payload.map {
            GitHubRelease(tagName: $0.tagName, htmlURL: $0.htmlURL, isDraft: $0.draft, isPrerelease: $0.prerelease)
        }
        return Self.latestAvailableUpdate(currentVersion: currentVersion, releases: releases)
    }

    public static func latestAvailableUpdate(
        currentVersion: SemanticVersion,
        releases: [GitHubRelease]
    ) -> AvailableUpdate? {
        releases
            .filter { !$0.isDraft }
            .compactMap { release -> AvailableUpdate? in
                guard let version = SemanticVersion(release.tagName) else { return nil }
                return AvailableUpdate(
                    version: version,
                    releaseURL: release.htmlURL,
                    isPrerelease: release.isPrerelease
                )
            }
            .filter { $0.version > currentVersion }
            .max { $0.version < $1.version }
    }
}
