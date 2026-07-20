import Foundation

public struct RolloutRecoveryCheckpointParser: Sendable {
    public static let maximumBytes = 2 * 1024 * 1024
    private let expectedUserMessage: String

    public init(expectedUserMessage: String) {
        self.expectedUserMessage = Self.normalize(expectedUserMessage)
    }

    public func parse(fileURL: URL) throws -> RolloutRecoveryCheckpoint {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let start = size > UInt64(Self.maximumBytes)
            ? size - UInt64(Self.maximumBytes)
            : 0
        try handle.seek(toOffset: start)
        var data = try handle.readToEnd() ?? Data()

        if start > 0 {
            guard let newline = data.firstIndex(of: 0x0A) else {
                return RolloutRecoveryCheckpoint(
                    latestUserMessageAt: nil,
                    latestTaskStartedAt: nil
                )
            }
            data.removeSubrange(data.startIndex...newline)
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \ .isNewline)
            .map(String.init)
        return parse(lines: lines)
    }

    public func parse(lines: [String]) -> RolloutRecoveryCheckpoint {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var latestUserMessageAt: Date?
        var latestTaskStartedAt: Date?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(EventEnvelope.self, from: data),
                  event.type == "event_msg" else {
                continue
            }

            switch event.payload.type {
            case "user_message":
                guard let message = event.payload.message,
                      Self.normalize(message) == expectedUserMessage else {
                    continue
                }
                latestUserMessageAt = max(latestUserMessageAt ?? .distantPast, event.timestamp)
            case "task_started":
                latestTaskStartedAt = max(latestTaskStartedAt ?? .distantPast, event.timestamp)
            default:
                continue
            }
        }

        return RolloutRecoveryCheckpoint(
            latestUserMessageAt: latestUserMessageAt,
            latestTaskStartedAt: latestTaskStartedAt
        )
    }

    private static func normalize(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct EventEnvelope: Decodable {
    let timestamp: Date
    let type: String
    let payload: EventPayload
}

private struct EventPayload: Decodable {
    let type: String
    let message: String?
}
