import Foundation
import ThreadBeaconCore

let windowPlacementTests = [
    TestCase(name: "window placement restores on the saved display") {
        let placement = WindowPlacement(
            displayIdentifier: "secondary",
            frame: WindowGeometry(x: 1600, y: 100, width: 420, height: 360)
        )
        let displays = [
            DisplayGeometry(
                identifier: "main",
                visibleFrame: WindowGeometry(x: 0, y: 0, width: 1440, height: 900)
            ),
            DisplayGeometry(
                identifier: "secondary",
                visibleFrame: WindowGeometry(x: 1440, y: 0, width: 1280, height: 800)
            )
        ]

        let restored = WindowPlacementResolver.resolve(
            placement,
            displays: displays,
            fallbackDisplayIdentifier: "main"
        )

        try expect(restored == placement, "a visible saved frame should be restored without changes")
    },
    TestCase(name: "window placement falls back to a visible display") {
        let placement = WindowPlacement(
            displayIdentifier: "disconnected",
            frame: WindowGeometry(x: 3000, y: -500, width: 420, height: 360)
        )
        let main = DisplayGeometry(
            identifier: "main",
            visibleFrame: WindowGeometry(x: 0, y: 25, width: 1440, height: 875)
        )

        let restored = WindowPlacementResolver.resolve(
            placement,
            displays: [main],
            fallbackDisplayIdentifier: "main"
        )

        try expect(restored?.displayIdentifier == "main", "a missing display should use the fallback")
        try expect(restored?.frame == WindowGeometry(x: 1020, y: 25, width: 420, height: 360),
                   "the fallback frame should be clamped inside the visible area")
    },
    TestCase(name: "window placement fits oversized frames on small displays") {
        let placement = WindowPlacement(
            displayIdentifier: "small",
            frame: WindowGeometry(x: 0, y: 0, width: 900, height: 700)
        )
        let small = DisplayGeometry(
            identifier: "small",
            visibleFrame: WindowGeometry(x: 100, y: 50, width: 480, height: 320)
        )

        let restored = WindowPlacementResolver.resolve(
            placement,
            displays: [small],
            fallbackDisplayIdentifier: nil
        )

        try expect(restored?.frame == small.visibleFrame,
                   "an oversized frame should fit the display visible area")
    },
    TestCase(name: "window placement repository round trips local geometry") {
        let suiteName = "WindowPlacementTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = WindowPlacementRepository(defaults: defaults)
        let placement = WindowPlacement(
            displayIdentifier: "display-42",
            frame: WindowGeometry(x: 10, y: 20, width: 420, height: 360)
        )

        repository.save(placement)

        try expect(repository.load() == placement, "saved placement should be restored")
    }
]
