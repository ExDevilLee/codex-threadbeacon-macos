import Foundation
import ThreadBeaconCore

let githubReleaseClientTests = [
    TestCase(name: "release selection keeps prerelease and ignores drafts") {
        let releases = [
            GitHubRelease(
                tagName: "v0.3.0",
                htmlURL: URL(string: "https://example.com/v0.3.0")!,
                isDraft: true,
                isPrerelease: false
            ),
            GitHubRelease(
                tagName: "v0.2.0-beta.1",
                htmlURL: URL(string: "https://example.com/v0.2.0-beta.1")!,
                isDraft: false,
                isPrerelease: true
            )
        ]

        let update = GitHubReleaseClient.latestAvailableUpdate(
            currentVersion: SemanticVersion("0.1.0")!,
            releases: releases
        )

        try expect(update?.version.description == "0.2.0-beta.1",
                   "technical previews should remain eligible")
        try expect(update?.releaseURL == releases[1].htmlURL,
                   "selected release URL should be preserved")
    },
    TestCase(name: "release selection uses semantic ordering and skips invalid tags") {
        let releases = [
            GitHubRelease(
                tagName: "not-a-version",
                htmlURL: URL(string: "https://example.com/invalid")!,
                isDraft: false,
                isPrerelease: false
            ),
            GitHubRelease(
                tagName: "v0.10.0",
                htmlURL: URL(string: "https://example.com/v0.10.0")!,
                isDraft: false,
                isPrerelease: false
            ),
            GitHubRelease(
                tagName: "v0.9.9",
                htmlURL: URL(string: "https://example.com/v0.9.9")!,
                isDraft: false,
                isPrerelease: false
            )
        ]

        let update = GitHubReleaseClient.latestAvailableUpdate(
            currentVersion: SemanticVersion("0.1.0")!,
            releases: releases
        )

        try expect(update?.version.description == "0.10.0",
                   "highest semantic version should win regardless of API order")
    },
    TestCase(name: "release selection reports no update for equal or older releases") {
        let releases = [
            GitHubRelease(
                tagName: "v0.1.0",
                htmlURL: URL(string: "https://example.com/v0.1.0")!,
                isDraft: false,
                isPrerelease: true
            ),
            GitHubRelease(
                tagName: "v0.0.9",
                htmlURL: URL(string: "https://example.com/v0.0.9")!,
                isDraft: false,
                isPrerelease: false
            )
        ]

        let update = GitHubReleaseClient.latestAvailableUpdate(
            currentVersion: SemanticVersion("0.1.0")!,
            releases: releases
        )

        try expect(update == nil, "equal and older releases should not show an update")
    }
]
