import Foundation
import ThreadBeaconCore

let relativeActivityFormatterTests = [
    TestCase(name: "relative activity uses stable Chinese units") {
        let now = Date(timeIntervalSince1970: 100_000)

        try expect(
            RelativeActivityFormatter.string(
                since: now.addingTimeInterval(-20 * 3_600 - 35 * 60),
                now: now
            ) == "20 小时前",
            "activity time should not depend on the process locale"
        )
    }
]
