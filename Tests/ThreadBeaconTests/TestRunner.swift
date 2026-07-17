import Foundation

@main
enum TestRunner {
    static func main() async {
        let tests = threadStatusTests
            + threadCountFormatterTests
            + monitoringModeTests
            + rolloutTailParserTests
            + soundNotificationTests
            + sqliteThreadRepositoryTests
            + subagentCountFormatterTests
            + sessionIndexTitleRepositoryTests
            + threadStatusLoaderTests
            + threadStatusStoreTests
            + tokenCountFormatterTests
            + windowPinModeTests
        var failures = 0

        for test in tests {
            do {
                try await test.body()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }

        print("\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 {
            exit(1)
        }
    }
}
