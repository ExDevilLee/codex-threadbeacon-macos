// swift-tools-version: 6.1

import PackageDescription

let languageModes: [SwiftLanguageMode] = [.v6]

let package = Package(
    name: "CodexThreadStatus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexThreadStatus", targets: ["CodexThreadStatus"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(
            name: "CodexThreadStatusCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "CodexThreadStatus",
            dependencies: ["CodexThreadStatusCore"]
        ),
        .executableTarget(
            name: "CodexThreadStatusTests",
            dependencies: ["CodexThreadStatusCore", "CSQLite"],
            path: "Tests/CodexThreadStatusTests"
        ),
        .executableTarget(
            name: "CodexThreadStatusProbe",
            dependencies: ["CodexThreadStatusCore"],
            path: "Tools/CodexThreadStatusProbe"
        )
    ],
    swiftLanguageModes: languageModes
)
