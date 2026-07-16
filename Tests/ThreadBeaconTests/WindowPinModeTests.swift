import ThreadBeaconCore

let windowPinModeTests = [
    TestCase(name: "window pin state maps to normal and floating modes") {
        try expect(WindowPinMode(isPinned: false) == .normal, "unpinned window should be normal")
        try expect(WindowPinMode(isPinned: true) == .floating, "pinned window should float")
    }
]
