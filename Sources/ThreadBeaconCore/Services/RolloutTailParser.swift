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
        var latestCompletionEventAt: Date?
        var latestTaskStartedAt: Date?
        var latestInterruptedAt: Date?
        var latestTokenUsage: TokenUsage?
        var latestTokenEventAt: Date?
        var currentTurnBaseline: TokenUsage?
        var latestModel: String?
        var latestReasoningEffort: String?

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
                if let payload = object["payload"] as? [String: Any] {
                    latestModel = normalizedString(payload["model"]) ?? latestModel
                    latestReasoningEffort = normalizedString(payload["effort"]) ?? latestReasoningEffort
                }
            }

            if object["type"] as? String == "event_msg",
               let payload = object["payload"] as? [String: Any],
               let eventType = payload["type"] as? String {
                if eventType == "task_started" {
                    currentTurnBaseline = latestTokenUsage
                    latestTaskStartedAt = max(latestTaskStartedAt ?? .distantPast, date)
                } else if eventType == "task_complete" {
                    latestCompletionEventAt = max(latestCompletionEventAt ?? .distantPast, date)
                } else if eventType == "turn_aborted",
                          payload["reason"] as? String == "interrupted" {
                    let completedAt = normalizedString(payload["completed_at"])
                        .flatMap(parseDate)
                    let interruptedAt = max(date, completedAt ?? .distantPast)
                    latestInterruptedAt = max(latestInterruptedAt ?? .distantPast, interruptedAt)
                    latestEvent = max(latestEvent ?? .distantPast, interruptedAt)
                } else if eventType == "token_count",
                          let usage = parseTokenUsage(from: payload) {
                    latestTokenUsage = usage
                    latestTokenEventAt = date
                }
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

        let latestRunningAt = [latestTurn, latestTaskStartedAt].compactMap { $0 }.max()
        let latestCompletedAt = [latestFinal, latestCompletionEventAt].compactMap { $0 }.max()
        let status: ThreadDisplayStatus
        let statusChangedAt: Date?
        if let latestCompletedAt,
           latestCompletedAt >= (latestInterruptedAt ?? .distantPast),
           latestCompletedAt >= (latestRunningAt ?? .distantPast) {
            status = .justCompleted
            statusChangedAt = latestCompletedAt
        } else if let latestInterruptedAt,
                  latestInterruptedAt >= (latestRunningAt ?? .distantPast) {
            status = .interrupted
            statusChangedAt = latestInterruptedAt
        } else if let latestRunningAt {
            status = .running
            statusChangedAt = latestRunningAt
        } else {
            status = .unknown
            statusChangedAt = nil
        }

        let tokenSnapshot = latestTokenUsage.map { usage in
            TokenUsageSnapshot(
                totalTokens: usage.totalTokens,
                cumulative: usage,
                currentTurn: currentTurnBaseline.flatMap(usage.subtracting),
                updatedAt: latestTokenEventAt
            )
        }

        return RolloutObservation(
            status: status,
            statusChangedAt: statusChangedAt,
            latestEventAt: latestEvent,
            completionEventAt: latestCompletionEventAt,
            latestTaskStartedAt: latestTaskStartedAt,
            tokenUsage: tokenSnapshot,
            model: latestModel,
            reasoningEffort: latestReasoningEffort
        )
    }

    private func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func parseTokenUsage(from payload: [String: Any]) -> TokenUsage? {
        guard
            let info = payload["info"] as? [String: Any],
            let totals = info["total_token_usage"] as? [String: Any],
            let input = nonnegativeInt64(totals["input_tokens"]),
            let cachedInput = nonnegativeInt64(totals["cached_input_tokens"]),
            let output = nonnegativeInt64(totals["output_tokens"]),
            let reasoningOutput = nonnegativeInt64(totals["reasoning_output_tokens"]),
            let total = nonnegativeInt64(totals["total_tokens"]),
            cachedInput <= input,
            reasoningOutput <= output
        else {
            return nil
        }
        return TokenUsage(
            inputTokens: input,
            cachedInputTokens: cachedInput,
            outputTokens: output,
            reasoningOutputTokens: reasoningOutput,
            totalTokens: total
        )
    }

    private func nonnegativeInt64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let integer = number.int64Value
        guard integer >= 0, number.doubleValue == Double(integer) else {
            return nil
        }
        return integer
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
