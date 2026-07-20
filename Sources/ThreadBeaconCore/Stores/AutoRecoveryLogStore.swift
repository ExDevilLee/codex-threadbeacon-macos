import Combine
import Foundation

@MainActor
public final class AutoRecoveryLogStore: ObservableObject {
    nonisolated public static let maximumEntries = 200

    @Published public private(set) var entries: [AutoRecoveryLogEntry] = []

    private let fileURL: URL
    private let now: () -> Date

    public init(
        fileURL: URL = AutoRecoveryLogStore.defaultFileURL,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    @discardableResult
    public func recordAttempt(
        threadID: String,
        episodeID: String,
        incident: String,
        prompt: String
    ) -> UUID {
        let entry = AutoRecoveryLogEntry(
            threadID: threadID,
            episodeID: episodeID,
            incident: incident,
            prompt: prompt,
            occurredAt: now()
        )
        entries.insert(entry, at: 0)
        persist()
        return entry.id
    }

    public func recordSuccess(_ id: UUID) {
        update(id) { entry in
            entry.status = .succeeded
            entry.completedAt = now()
            entry.detail = "Codex CLI 已接受提示词（进程退出码 0）"
        }
    }

    public func recordFailure(_ id: UUID, detail: String?) {
        update(id) { entry in
            entry.status = .failed
            entry.completedAt = now()
            entry.detail = Self.sanitize(detail)
        }
    }

    public func recordSkipped(_ id: UUID, detail: String = "需要 macOS Accessibility 授权") {
        update(id) { entry in
            entry.status = .skipped
            entry.completedAt = now()
            entry.detail = detail
        }
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    public static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThreadBeacon", isDirectory: true)
        return directory.appendingPathComponent("auto-recovery-log.json")
    }

    private func update(_ id: UUID, _ change: (inout AutoRecoveryLogEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AutoRecoveryLogEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(Self.maximumEntries))
    }

    private func persist() {
        entries = Array(entries.prefix(Self.maximumEntries))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func sanitize(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let singleLine = detail
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(300))
    }
}
