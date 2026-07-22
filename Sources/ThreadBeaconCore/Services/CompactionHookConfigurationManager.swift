import Foundation

public final class CompactionHookConfigurationManager: @unchecked Sendable {
    private static let managedEvents = ["PreCompact", "PostCompact"]

    private let hooksURL: URL
    private let configURL: URL
    private let applicationSupportURL: URL
    private let helperURL: URL
    private let backupURL: URL
    private let beforeReplace: @Sendable () -> Void
    private let fileManager: FileManager

    public init(
        hooksURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json"),
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml"),
        applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ThreadBeacon", isDirectory: true),
        beforeReplace: @escaping @Sendable () -> Void = {}
    ) {
        self.hooksURL = hooksURL
        self.configURL = configURL
        self.applicationSupportURL = applicationSupportURL
        helperURL = applicationSupportURL
            .appendingPathComponent("hooks/v1", isDirectory: true)
            .appendingPathComponent("ThreadBeaconHookBridge")
        backupURL = applicationSupportURL
            .appendingPathComponent("hook-backups", isDirectory: true)
            .appendingPathComponent("hooks.json.latest")
        self.beforeReplace = beforeReplace
        fileManager = .default
    }

    public func install(helperSourceURL: URL) throws -> CompactionHookConfigurationStatus {
        try rejectInlineHooks()
        let originalData = try readHooksData()
        var root = try decodeRoot(originalData)
        try installHelper(from: helperSourceURL)

        if let originalData {
            try createBackup(with: originalData)
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.managedEvents {
            hooks[event] = addingManagedHandler(to: hooks[event])
        }
        root["hooks"] = hooks

        let replacement: Data
        do {
            replacement = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw CompactionHookConfigurationError.writeFailed
        }

        beforeReplace()
        let currentData = try readHooksData()
        guard currentData == originalData else {
            throw CompactionHookConfigurationError.configurationChanged
        }
        try writeHooksAtomically(replacement)
        return status()
    }

    public func uninstall() throws {
        let originalData = try readHooksData()
        guard let originalData else {
            try? fileManager.removeItem(at: helperURL)
            return
        }
        var root = try decodeRoot(originalData)
        guard var hooks = root["hooks"] as? [String: Any] else {
            try? fileManager.removeItem(at: helperURL)
            return
        }

        for event in Self.managedEvents {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let remaining = groups.compactMap(removingManagedHandlers)
            if remaining.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = remaining
            }
        }
        root["hooks"] = hooks
        let replacement: Data
        do {
            replacement = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw CompactionHookConfigurationError.writeFailed
        }

        beforeReplace()
        let currentData = try readHooksData()
        guard currentData == originalData else {
            throw CompactionHookConfigurationError.configurationChanged
        }
        try writeHooksAtomically(replacement)
        try? fileManager.removeItem(at: helperURL)
        try? fileManager.removeItem(
            at: applicationSupportURL.appendingPathComponent("compaction/v1/active", isDirectory: true)
        )
    }

    public func status() -> CompactionHookConfigurationStatus {
        guard let data = try? readHooksData(),
              let root = try? decodeRoot(data),
              let hooks = root["hooks"] as? [String: Any] else {
            return fileManager.fileExists(atPath: helperURL.path) ? .externallyModified : .notConfigured
        }
        let counts = Self.managedEvents.map { event -> Int in
            guard let groups = hooks[event] as? [[String: Any]] else { return 0 }
            return groups.reduce(0) { count, group in
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                return count + handlers.filter(isManagedHandler).count
            }
        }
        let helperExists = fileManager.isExecutableFile(atPath: helperURL.path)
        if counts.allSatisfy({ $0 == 0 }) && !helperExists {
            return .notConfigured
        }
        if counts.allSatisfy({ $0 == 1 }) && helperExists {
            return .configured
        }
        return .externallyModified
    }

    private func rejectInlineHooks() throws {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        let hasInlineHooks = text.split(separator: "\n").contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { return false }
            return line.range(
                of: #"^\[\[?\s*hooks(?:\.|\s*\])"#,
                options: .regularExpression
            ) != nil
        }
        if hasInlineHooks {
            throw CompactionHookConfigurationError.inlineHooksPresent
        }
    }

    private func readHooksData() throws -> Data? {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return nil }
        let values: URLResourceValues
        do {
            values = try hooksURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw CompactionHookConfigurationError.unsafeHooksFile
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CompactionHookConfigurationError.unsafeHooksFile
        }
        do {
            return try Data(contentsOf: hooksURL)
        } catch {
            throw CompactionHookConfigurationError.unsafeHooksFile
        }
    }

    private func decodeRoot(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CompactionHookConfigurationError.invalidHooksJSON
            }
            return root
        } catch let error as CompactionHookConfigurationError {
            throw error
        } catch {
            throw CompactionHookConfigurationError.invalidHooksJSON
        }
    }

    private func installHelper(from sourceURL: URL) throws {
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw CompactionHookConfigurationError.helperUnavailable
        }
        do {
            try fileManager.createDirectory(
                at: helperURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: helperURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        } catch {
            throw CompactionHookConfigurationError.writeFailed
        }
    }

    private func createBackup(with data: Data) throws {
        do {
            try fileManager.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: backupURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } catch {
            throw CompactionHookConfigurationError.writeFailed
        }
    }

    private func writeHooksAtomically(_ data: Data) throws {
        do {
            try fileManager.createDirectory(
                at: hooksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: hooksURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)
        } catch {
            throw CompactionHookConfigurationError.writeFailed
        }
    }

    private func addingManagedHandler(to value: Any?) -> [[String: Any]] {
        var groups = value as? [[String: Any]] ?? []
        for index in groups.indices {
            var group = groups[index]
            var handlers = group["hooks"] as? [[String: Any]] ?? []
            handlers.removeAll(where: isManagedHandler)
            group["hooks"] = handlers
            groups[index] = group
        }
        groups.removeAll { ($0["hooks"] as? [[String: Any]])?.isEmpty == true }
        groups.append([
            "matcher": "manual|auto",
            "hooks": [[
                "type": "command",
                "command": shellQuote(helperURL.path),
                "timeout": 3
            ]]
        ])
        return groups
    }

    private func removingManagedHandlers(from group: [String: Any]) -> [String: Any]? {
        guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
        handlers.removeAll(where: isManagedHandler)
        guard !handlers.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = handlers
        return updated
    }

    private func isManagedHandler(_ handler: [String: Any]) -> Bool {
        guard handler["type"] as? String == "command",
              let command = handler["command"] as? String else {
            return false
        }
        return command == shellQuote(helperURL.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
