import Foundation

@main
enum TestRunner {
    static func main() async {
        let tests = threadStatusTests
            + accessibilityDiagnosticTests
            + autoRecoveryLogStoreTests
            + autoRecoverySettingsTests
            + aboutAppInfoTests
            + appLanguageTests
            + appLanguageStoreTests
            + appThemeTests
            + archiveRestoreAvailabilityTests
            + codexArchiveRestoreServiceTests
            + codexMessageSendServiceTests
            + codexCLIResolverTests
            + dataSourceHealthTests
            + displaySettingsTests
            + threadCountFormatterTests
            + monitoringModeTests
            + threadListPolicyTests
            + threadListPreferenceRepositoryTests
            + logEventParserTests
            + logEventRepositoryTests
            + launchAtLoginTests
            + relativeActivityFormatterTests
            + rolloutTailParserTests
            + soundNotificationTests
            + semanticVersionTests
            + githubReleaseClientTests
            + updateCheckStoreTests
            + sqliteThreadRepositoryTests
            + subagentCountFormatterTests
            + sessionIndexTitleRepositoryTests
            + subagentAliasFormatterTests
            + threadStatusLoaderTests
            + threadStatusStoreTests
            + tokenCountFormatterTests
            + windowPlacementTests
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
