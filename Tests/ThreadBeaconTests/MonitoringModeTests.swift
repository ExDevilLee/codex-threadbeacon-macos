import ThreadBeaconCore

let monitoringModeTests = [
    TestCase(name: "monitoring mode toggles automatic refresh") {
        var mode = MonitoringMode.active
        try expect(mode.shouldAutoRefresh, "active mode should refresh automatically")

        mode.toggle()
        try expect(mode == .paused, "first toggle should pause monitoring")
        try expect(!mode.shouldAutoRefresh, "paused mode must stop automatic refresh")

        mode.toggle()
        try expect(mode == .active, "second toggle should resume monitoring")
    }
]
