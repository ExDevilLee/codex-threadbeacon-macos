import Foundation

public final class CompactionHistoryRepository: @unchecked Sendable {
    private enum EventKind: Equatable {
        case compacted
        case contextCompacted
    }

    private struct Candidate {
        let kind: EventKind
        let date: Date
    }

    private struct FileState {
        var fileNumber: UInt64
        var modificationDate: Date?
        var offset: UInt64 = 0
        var trailingData = Data()
        var completionCount = 0
        var lastCompletedAt: Date?
        var lastCandidate: Candidate?

        var history: CompactionHistory {
            CompactionHistory(
                completionCount: completionCount,
                lastCompletedAt: lastCompletedAt
            )
        }
    }

    private let lock = NSLock()
    private var states: [String: FileState] = [:]

    public init() {}

    public func history(for fileURL: URL) throws -> CompactionHistory {
        try lock.withLock {
            try historyWhileLocked(for: fileURL.standardizedFileURL)
        }
    }

    private func historyWhileLocked(for fileURL: URL) throws -> CompactionHistory {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        let key = fileURL.path

        var state = states[key] ?? FileState(
            fileNumber: fileNumber,
            modificationDate: modificationDate
        )
        let wasReplaced = state.fileNumber != fileNumber
        let wasTruncated = fileSize < state.offset
        let wasRewrittenAtSameSize = fileSize == state.offset
            && state.offset > 0
            && state.modificationDate != modificationDate
        if wasReplaced || wasTruncated || wasRewrittenAtSameSize {
            state = FileState(fileNumber: fileNumber, modificationDate: modificationDate)
        }

        guard fileSize > state.offset else {
            state.modificationDate = modificationDate
            states[key] = state
            return state.history
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: state.offset)
        let appendedData = try handle.readToEnd() ?? Data()
        state.offset += UInt64(appendedData.count)
        state.modificationDate = modificationDate

        var combined = state.trailingData
        combined.append(appendedData)
        let segments = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
        let hasCompleteLastLine = combined.last == 0x0A
        let completeSegments = segments.dropLast()
        state.trailingData = hasCompleteLastLine
            ? Data()
            : Data(segments.last ?? Data.SubSequence())

        for segment in completeSegments where !segment.isEmpty {
            guard let candidate = parseCandidate(from: Data(segment)) else {
                continue
            }
            apply(candidate, to: &state)
        }

        states[key] = state
        return state.history
    }

    private func apply(_ candidate: Candidate, to state: inout FileState) {
        state.lastCompletedAt = max(state.lastCompletedAt ?? .distantPast, candidate.date)
        if let previous = state.lastCandidate,
           previous.kind != candidate.kind,
           abs(candidate.date.timeIntervalSince(previous.date)) <= 2 {
            state.lastCandidate = nil
            return
        }
        state.completionCount += 1
        state.lastCandidate = candidate
    }

    private func parseCandidate(from data: Data) -> Candidate? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let timestamp = object["timestamp"] as? String,
            let date = parseDate(timestamp)
        else {
            return nil
        }

        if object["type"] as? String == "compacted" {
            return Candidate(kind: .compacted, date: date)
        }
        if object["type"] as? String == "event_msg",
           let payload = object["payload"] as? [String: Any],
           payload["type"] as? String == "context_compacted" {
            return Candidate(kind: .contextCompacted, date: date)
        }
        return nil
    }

    private func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
