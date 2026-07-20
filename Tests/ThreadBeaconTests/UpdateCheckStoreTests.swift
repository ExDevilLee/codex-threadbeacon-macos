import Foundation
import ThreadBeaconCore

let updateCheckStoreTests = [
    TestCase(name: "update store automatically checks only once") {
        let counter = CallCounter()
        let store = await MainActor.run {
            UpdateCheckStore(currentVersion: "0.1.0") { _ in
                await counter.increment()
                return nil
            }
        }

        await store.checkAutomatically()
        await store.checkAutomatically()

        let automaticCallCount = await counter.value
        try expect(automaticCallCount == 1, "automatic check should run once per store lifetime")
        let automaticState = await store.state
        try expect(automaticState == .upToDate, "no newer release should publish up to date")
    },
    TestCase(name: "update store publishes available release") {
        let release = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            releaseURL: URL(string: "https://example.com/v0.2.0")!,
            isPrerelease: true
        )
        let store = await MainActor.run {
            UpdateCheckStore(currentVersion: "0.1.0") { _ in release }
        }

        await store.checkManually()

        let availableResult = await MainActor.run { (store.state, store.availableUpdate) }
        try expect(availableResult.0 == .updateAvailable(release),
                   "newer release should be exposed to every window")
        try expect(availableResult.1 == release,
                   "available update convenience value should match state")
    },
    TestCase(name: "update store allows manual retry after failure") {
        let counter = CallCounter()
        let release = AvailableUpdate(
            version: SemanticVersion("0.2.0")!,
            releaseURL: URL(string: "https://example.com/v0.2.0")!,
            isPrerelease: false
        )
        let store = await MainActor.run {
            UpdateCheckStore(currentVersion: "0.1.0") { _ in
                let call = await counter.increment()
                if call == 1 { throw UpdateCheckTestError.failed }
                return release
            }
        }

        await store.checkManually()
        let failedState = await store.state
        try expect(failedState == .failed, "first failure should be represented without raw details")

        await store.checkManually()
        let retryState = await store.state
        try expect(retryState == .updateAvailable(release), "manual retry should replace failure state")
        let manualCallCount = await counter.value
        try expect(manualCallCount == 2, "manual checks should remain repeatable")
    },
    TestCase(name: "update store skips network when current version is invalid") {
        let counter = CallCounter()
        let store = await MainActor.run {
            UpdateCheckStore(currentVersion: nil) { _ in
                await counter.increment()
                return nil
            }
        }

        await store.checkManually()

        let invalidVersionState = await store.state
        try expect(invalidVersionState == .currentVersionUnavailable,
                   "missing bundle version should have a stable state")
        let invalidVersionCallCount = await counter.value
        try expect(invalidVersionCallCount == 0, "invalid current version should not perform a request")
    }
]

private enum UpdateCheckTestError: Error { case failed }

private actor CallCounter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
