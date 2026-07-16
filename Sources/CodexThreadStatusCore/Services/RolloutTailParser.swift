import Foundation

public struct RolloutTailParser: Sendable {
    public static let maximumBytes = 2 * 1024 * 1024

    public init() {}

    public func parse(fileURL: URL) throws -> RolloutObservation {
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
                return RolloutObservation()
            }
            data.removeSubrange(data.startIndex...newline)
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \ .isNewline)
            .map(String.init)
        return parse(lines: lines)
    }

    public func parse(lines: [String]) -> RolloutObservation {
        var latestTurn: Date?
        var latestFinal: Date?
        var latestEvent: Date?

        for line in lines {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let timestamp = object["timestamp"] as? String,
                let date = parseDate(timestamp)
            else {
                continue
            }
            latestEvent = max(latestEvent ?? .distantPast, date)

            if object["type"] as? String == "turn_context" {
                latestTurn = max(latestTurn ?? .distantPast, date)
            }

            guard
                object["type"] as? String == "response_item",
                let payload = object["payload"] as? [String: Any]
            else {
                continue
            }

            if payload["type"] as? String == "message",
               payload["role"] as? String == "assistant",
               let phase = payload["phase"] as? String,
               phase == "final" || phase == "final_answer" {
                latestFinal = max(latestFinal ?? .distantPast, date)
            }

        }

        let status: ThreadDisplayStatus
        let statusChangedAt: Date?
        if let latestTurn, latestTurn > (latestFinal ?? .distantPast) {
            status = .running
            statusChangedAt = latestTurn
        } else if let latestFinal {
            status = .justCompleted
            statusChangedAt = latestFinal
        } else {
            status = .unknown
            statusChangedAt = latestTurn
        }

        return RolloutObservation(
            status: status,
            statusChangedAt: statusChangedAt,
            latestEventAt: latestEvent
        )
    }

    private func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
