import ThreadBeaconCore

let aboutAppInfoTests = [
    TestCase(name: "about info reads version and build") {
        let info = AboutAppInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1"
        ])

        try expect(info.version == "0.1.0", "version should be read")
        try expect(info.build == "1", "build should be read")
    },
    TestCase(name: "about info trims empty values") {
        let info = AboutAppInfo(infoDictionary: [
            "CFBundleShortVersionString": "  ",
            "CFBundleVersion": "7"
        ])

        try expect(info.version == nil, "empty version should be absent")
        try expect(info.build == "7", "build should remain available")
    },
    TestCase(name: "about info handles a missing dictionary") {
        let info = AboutAppInfo(infoDictionary: nil)

        try expect(info.version == nil, "missing version should be absent")
        try expect(info.build == nil, "missing build should be absent")
    }
]
