import Foundation

public final class CompactionActivityRepository: @unchecked Sendable {
    public static let defaultTTL: TimeInterval = 15 * 60
    public static let futureTolerance: TimeInterval = 60

    private struct Marker: Codable {
        let schemaVersion: Int
        let sessionID: String
        let turnID: String
        let trigger: CompactionTrigger
        let startedAt: Date
    }

    private struct Diagnostic: Codable {
        let schemaVersion: Int
        let code: String
        let occurredAt: Date
    }

    private let directoryURL: URL
    private let ttl: TimeInterval
    private let lock = NSLock()

    public init(
        directoryURL: URL = CompactionActivityRepository.defaultDirectoryURL,
        ttl: TimeInterval = CompactionActivityRepository.defaultTTL
    ) {
        self.directoryURL = directoryURL
        self.ttl = ttl
    }

    public static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThreadBeacon/compaction/v1/active", isDirectory: true)
    }

    public func write(_ activity: CompactionActivity) throws {
        try lock.withLock {
            guard
                let sessionID = normalizedUUID(activity.sessionID),
                let turnID = normalizedUUID(activity.turnID)
            else {
                throw CompactionHookEventError.invalidIdentifier
            }
            let marker = Marker(
                schemaVersion: 1,
                sessionID: sessionID,
                turnID: turnID,
                trigger: activity.trigger,
                startedAt: activity.startedAt
            )
            try writeJSON(marker, to: markerURL(forNormalizedSessionID: sessionID))
        }
    }

    public func clear(sessionID: String, turnID: String) throws {
        try lock.withLock {
            guard
                let normalizedSessionID = normalizedUUID(sessionID),
                let normalizedTurnID = normalizedUUID(turnID)
            else {
                throw CompactionHookEventError.invalidIdentifier
            }
            let url = markerURL(forNormalizedSessionID: normalizedSessionID)
            guard
                let data = try? Data(contentsOf: url),
                let marker = try? decoder().decode(Marker.self, from: data),
                marker.schemaVersion == 1,
                marker.sessionID == normalizedSessionID,
                marker.turnID == normalizedTurnID
            else {
                return
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func activity(
        for sessionID: String,
        completionEvidenceAt: Date? = nil,
        interruptionEvidenceAt: Date? = nil,
        now: Date = Date()
    ) -> CompactionActivity? {
        lock.withLock {
            guard let normalizedSessionID = normalizedUUID(sessionID) else {
                return nil
            }
            let url = markerURL(forNormalizedSessionID: normalizedSessionID)
            guard
                let data = try? Data(contentsOf: url),
                let marker = try? decoder().decode(Marker.self, from: data),
                marker.schemaVersion == 1,
                marker.sessionID == normalizedSessionID,
                normalizedUUID(marker.turnID) == marker.turnID,
                marker.startedAt <= now.addingTimeInterval(Self.futureTolerance),
                now.timeIntervalSince(marker.startedAt) <= ttl,
                completionEvidenceAt.map({ $0 < marker.startedAt }) ?? true,
                interruptionEvidenceAt.map({ $0 < marker.startedAt }) ?? true
            else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return CompactionActivity(
                sessionID: marker.sessionID,
                turnID: marker.turnID,
                trigger: marker.trigger,
                startedAt: marker.startedAt
            )
        }
    }

    public func recordDiagnostic(code: String, at date: Date = Date()) {
        lock.withLock {
            let diagnostic = Diagnostic(schemaVersion: 1, code: code, occurredAt: date)
            let url = directoryURL.deletingLastPathComponent().appendingPathComponent("last-error.json")
            try? writeJSON(diagnostic, to: url)
        }
    }

    private func markerURL(forNormalizedSessionID sessionID: String) -> URL {
        directoryURL.appendingPathComponent(sessionID).appendingPathExtension("json")
    }

    private func normalizedUUID(_ value: String) -> String? {
        UUID(uuidString: value)?.uuidString.lowercased()
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encoder().encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
