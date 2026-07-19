// swift-tools-version: 6.1

import PackageDescription

let languageModes: [SwiftLanguageMode] = [.v6]

let package = Package(
    name: "ThreadBeacon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ThreadBeacon", targets: ["ThreadBeacon"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(
            name: "ThreadBeaconCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "ThreadBeacon",
            dependencies: ["ThreadBeaconCore"],
            resources: [.process("../../Resources/Localizable.xcstrings")]
        ),
        .executableTarget(
            name: "ThreadBeaconTests",
            dependencies: ["ThreadBeaconCore", "CSQLite"],
            path: "Tests/ThreadBeaconTests"
        ),
        .executableTarget(
            name: "ThreadBeaconProbe",
            dependencies: ["ThreadBeaconCore"],
            path: "Tools/ThreadBeaconProbe"
        )
    ],
    swiftLanguageModes: languageModes
)
