import Foundation
import ThreadBeaconCore

let compactionHookConfigurationManagerTests = [
    TestCase(name: "compaction hook installer creates config and stable helper") {
        let fixture = try CompactionHookConfigurationFixture()
        defer { fixture.remove() }

        let result = try fixture.manager.install(helperSourceURL: fixture.helperSourceURL)
        let root = try fixture.readHooks()

        try expect(result == .configured, "install should report configured")
        try expect(fixture.manager.status() == .configured, "installed files should validate")
        try expect(fixture.handlerCount(in: root, event: "PreCompact") == 1, "PreCompact should be installed")
        try expect(fixture.handlerCount(in: root, event: "PostCompact") == 1, "PostCompact should be installed")
        try expect(FileManager.default.isExecutableFile(atPath: fixture.helperDestinationURL.path), "helper should be executable")
    },
    TestCase(name: "compaction hook installer preserves existing hooks and is idempotent") {
        let fixture = try CompactionHookConfigurationFixture(existingHooks: [
            "description": "Existing hooks",
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "/usr/bin/true"]]]]
            ]
        ])
        defer { fixture.remove() }

        _ = try fixture.manager.install(helperSourceURL: fixture.helperSourceURL)
        _ = try fixture.manager.install(helperSourceURL: fixture.helperSourceURL)
        let root = try fixture.readHooks()

        try expect(root["description"] as? String == "Existing hooks", "top-level metadata should remain")
        try expect(fixture.handlerCount(in: root, event: "Stop") == 1, "existing event should remain")
        try expect(fixture.handlerCount(in: root, event: "PreCompact") == 1, "repeat install should not duplicate")
        try expect(FileManager.default.fileExists(atPath: fixture.backupURL.path), "existing config should be backed up")
    },
    TestCase(name: "compaction hook uninstaller removes only owned handlers") {
        let fixture = try CompactionHookConfigurationFixture(existingHooks: [
            "hooks": [
                "PreCompact": [[
                    "matcher": "manual|auto",
                    "hooks": [["type": "command", "command": "/usr/bin/existing-hook"]]
                ]]
            ]
        ])
        defer { fixture.remove() }
        _ = try fixture.manager.install(helperSourceURL: fixture.helperSourceURL)

        try fixture.manager.uninstall()
        let root = try fixture.readHooks()

        try expect(fixture.handlerCount(in: root, event: "PreCompact") == 1, "existing handler should remain")
        try expect(fixture.manager.status() == .notConfigured, "owned handlers and helper should be removed")
    },
    TestCase(name: "compaction hook installer rejects malformed JSON") {
        let fixture = try CompactionHookConfigurationFixture(rawHooks: Data("not-json".utf8))
        defer { fixture.remove() }

        do {
            _ = try fixture.manager.install(helperSourceURL: fixture.helperSourceURL)
            throw TestFailure(description: "malformed JSON should fail")
        } catch let error as CompactionHookConfigurationError {
            try expect(error == .invalidHooksJSON, "malformed JSON should have a stable error")
        }
        let unchangedData = try Data(contentsOf: fixture.hooksURL)
        try expect(unchangedData == Data("not-json".utf8), "invalid config must remain unchanged")
    },
    TestCase(name: "compaction hook installer rejects symlink and inline TOML hooks") {
        let symlinkFixture = try CompactionHookConfigurationFixture(symlinkHooks: true)
        defer { symlinkFixture.remove() }
        do {
            _ = try symlinkFixture.manager.install(helperSourceURL: symlinkFixture.helperSourceURL)
            throw TestFailure(description: "symlink should fail")
        } catch let error as CompactionHookConfigurationError {
            try expect(error == .unsafeHooksFile, "symlink should be classified as unsafe")
        }

        let inlineFixture = try CompactionHookConfigurationFixture(configTOML: "[hooks]\n")
        defer { inlineFixture.remove() }
        do {
            _ = try inlineFixture.manager.install(helperSourceURL: inlineFixture.helperSourceURL)
            throw TestFailure(description: "inline hooks should fail")
        } catch let error as CompactionHookConfigurationError {
            try expect(error == .inlineHooksPresent, "inline hooks should require manual setup")
        }
    },
    TestCase(name: "compaction hook installer stops after concurrent config change") {
        let fixture = try CompactionHookConfigurationFixture(existingHooks: ["hooks": [:]])
        defer { fixture.remove() }
        let replacement = try JSONSerialization.data(withJSONObject: ["description": "external", "hooks": [:]])
        let manager = fixture.makeManager(beforeReplace: {
            try? replacement.write(to: fixture.hooksURL, options: .atomic)
        })

        do {
            _ = try manager.install(helperSourceURL: fixture.helperSourceURL)
            throw TestFailure(description: "concurrent update should fail")
        } catch let error as CompactionHookConfigurationError {
            try expect(error == .configurationChanged, "concurrent update should be classified")
        }
        let root = try fixture.readHooks()
        try expect(root["description"] as? String == "external", "external update must not be overwritten")
    },
    TestCase(name: "compaction hook settings store publishes install and uninstall status") {
        let fixture = try CompactionHookConfigurationFixture()
        defer { fixture.remove() }

        let result = await MainActor.run { () -> (
            CompactionHookConfigurationStatus,
            CompactionHookConfigurationError?,
            CompactionHookConfigurationStatus,
            CompactionHookConfigurationError?
        ) in
            let store = CompactionHookSettingsStore(manager: fixture.manager)
            store.install(helperSourceURL: fixture.helperSourceURL)
            let installedStatus = store.status
            let installError = store.lastError
            store.uninstall()
            return (installedStatus, installError, store.status, store.lastError)
        }

        try expect(result.0 == .configured, "store should publish configured after install")
        try expect(result.1 == nil, "successful install should clear the error")
        try expect(result.2 == .notConfigured, "store should publish not configured after uninstall")
        try expect(result.3 == nil, "successful uninstall should clear the error")
    },
    TestCase(name: "compaction hook settings store retains a stable configuration error") {
        let fixture = try CompactionHookConfigurationFixture(rawHooks: Data("not-json".utf8))
        defer { fixture.remove() }

        let result = await MainActor.run { () -> (
            CompactionHookConfigurationStatus,
            CompactionHookConfigurationError?
        ) in
            let store = CompactionHookSettingsStore(manager: fixture.manager)
            store.install(helperSourceURL: fixture.helperSourceURL)
            return (store.status, store.lastError)
        }

        try expect(result.0 == .notConfigured, "failed install should not claim configuration")
        try expect(result.1 == .invalidHooksJSON, "store should retain the stable failure reason")
    }
]

private final class CompactionHookConfigurationFixture: @unchecked Sendable {
    let rootURL: URL
    let codexURL: URL
    let hooksURL: URL
    let configURL: URL
    let supportURL: URL
    let helperSourceURL: URL
    let helperDestinationURL: URL
    let backupURL: URL
    let manager: CompactionHookConfigurationManager

    init(
        existingHooks: [String: Any]? = nil,
        rawHooks: Data? = nil,
        symlinkHooks: Bool = false,
        configTOML: String? = nil
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThreadBeaconHookConfigTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        codexURL = rootURL.appendingPathComponent(".codex", isDirectory: true)
        hooksURL = codexURL.appendingPathComponent("hooks.json")
        configURL = codexURL.appendingPathComponent("config.toml")
        supportURL = rootURL.appendingPathComponent("Application Support/ThreadBeacon", isDirectory: true)
        helperSourceURL = rootURL.appendingPathComponent("source-helper")
        helperDestinationURL = supportURL.appendingPathComponent("hooks/v1/ThreadBeaconHookBridge")
        backupURL = supportURL.appendingPathComponent("hook-backups/hooks.json.latest")
        try FileManager.default.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try Data("helper".utf8).write(to: helperSourceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperSourceURL.path)
        if let configTOML {
            try configTOML.write(to: configURL, atomically: true, encoding: .utf8)
        }
        if symlinkHooks {
            let target = rootURL.appendingPathComponent("target.json")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: hooksURL, withDestinationURL: target)
        } else if let rawHooks {
            try rawHooks.write(to: hooksURL)
        } else if let existingHooks {
            try JSONSerialization.data(withJSONObject: existingHooks).write(to: hooksURL)
        }
        manager = CompactionHookConfigurationManager(
            hooksURL: hooksURL,
            configURL: configURL,
            applicationSupportURL: supportURL
        )
    }

    func makeManager(
        beforeReplace: @escaping @Sendable () -> Void
    ) -> CompactionHookConfigurationManager {
        CompactionHookConfigurationManager(
            hooksURL: hooksURL,
            configURL: configURL,
            applicationSupportURL: supportURL,
            beforeReplace: beforeReplace
        )
    }

    func readHooks() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL))
        return object as? [String: Any] ?? [:]
    }

    func handlerCount(in root: [String: Any], event: String) -> Int {
        guard
            let hooks = root["hooks"] as? [String: Any],
            let groups = hooks[event] as? [[String: Any]]
        else {
            return 0
        }
        return groups.reduce(0) { count, group in
            count + ((group["hooks"] as? [[String: Any]])?.count ?? 0)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
