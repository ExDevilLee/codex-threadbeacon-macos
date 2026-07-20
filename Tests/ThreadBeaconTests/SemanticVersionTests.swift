import ThreadBeaconCore

let semanticVersionTests = [
    TestCase(name: "semantic version accepts release tags with optional v prefix") {
        let plain = SemanticVersion("0.2.0")
        let prefixed = SemanticVersion("v0.2.0")

        try expect(plain == prefixed, "v prefix should not affect the version")
        try expect(prefixed?.description == "0.2.0", "description should be normalized")
    },
    TestCase(name: "semantic version compares numeric components numerically") {
        let older = SemanticVersion("0.9.9")
        let newer = SemanticVersion("0.10.0")

        try expect(older != nil && newer != nil, "versions should parse")
        try expect(older! < newer!, "minor components should not use string ordering")
    },
    TestCase(name: "semantic version orders prerelease before stable") {
        let beta = SemanticVersion("1.0.0-beta.2")
        let stable = SemanticVersion("1.0.0")

        try expect(beta != nil && stable != nil, "versions should parse")
        try expect(beta! < stable!, "prerelease should precede stable")
    },
    TestCase(name: "semantic version applies numeric prerelease ordering") {
        let betaTwo = SemanticVersion("1.0.0-beta.2")
        let betaTen = SemanticVersion("1.0.0-beta.10")

        try expect(betaTwo != nil && betaTen != nil, "versions should parse")
        try expect(betaTwo! < betaTen!, "numeric prerelease identifiers should compare numerically")
    },
    TestCase(name: "semantic version accepts hyphens inside prerelease identifiers") {
        let version = SemanticVersion("1.0.0-alpha-beta.1")

        try expect(version?.description == "1.0.0-alpha-beta.1",
                   "hyphens are valid inside a prerelease identifier")
    },
    TestCase(name: "semantic version rejects incomplete or malformed values") {
        try expect(SemanticVersion("1.2") == nil, "patch component is required")
        try expect(SemanticVersion("release-1.2.3") == nil, "unknown prefixes should fail")
        try expect(SemanticVersion("1.2.3-") == nil, "empty prerelease should fail")
        try expect(SemanticVersion("1.2.3+bad!") == nil, "invalid build metadata should fail")
    }
]
