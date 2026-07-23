import Foundation

public struct LogEventParser: Sendable {
    public static let allowedTargets: Set<String> = [
        "codex_http_client::default_client",
        "codex_core::responses_retry",
        "codex_core::session::turn"
    ]

    public init() {}

    public func latestIncidents(from records: [LogEventRecord]) -> [String: ServiceIncident] {
        var episodes: [EpisodeKey: Episode] = [:]

        for record in records.sorted(by: recordPrecedes) {
            guard Self.allowedTargets.contains(record.target),
                  let episodeID = firstCapture(
                    in: record.body,
                    patterns: [#"turn\.id=([A-Za-z0-9-]+)"#, #"turn_id=([A-Za-z0-9-]+)"#]
                  ) else {
                continue
            }
            let key = EpisodeKey(threadID: record.threadID, episodeID: episodeID)
            var episode = episodes[key] ?? Episode()

            switch record.target {
            case "codex_http_client::default_client":
                if let status = statusCode(in: record.body) {
                    if status == 200 {
                        episode.latestSuccessAt = max(episode.latestSuccessAt, record.occurredAt)
                    } else if let kind = incidentKind(for: status) {
                        episode.kind = kind
                        episode.httpStatusCode = status
                        if kind == .badRequest {
                            episode.failedAt = max(episode.failedAt, record.occurredAt)
                        } else {
                            episode.latestErrorAt = max(episode.latestErrorAt, record.occurredAt)
                        }
                    }
                }
            case "codex_core::responses_retry":
                if let progress = retryProgress(in: record.body) {
                    episode.retryAttempt = progress.attempt
                    episode.retryLimit = progress.limit
                    episode.latestRetryAt = max(episode.latestRetryAt, record.occurredAt)
                }
            case "codex_core::session::turn":
                if record.body.contains("Turn error: Selected model is at capacity. Please try a different model.") {
                    episode.kind = .modelCapacity
                    episode.httpStatusCode = nil
                    episode.failedAt = max(episode.failedAt, record.occurredAt)
                } else if record.body.contains("Turn error: stream disconnected before completion:"),
                          let retryAttempt = episode.retryAttempt,
                          let retryLimit = episode.retryLimit,
                          retryAttempt == retryLimit {
                    episode.kind = .streamDisconnected
                    episode.httpStatusCode = nil
                    episode.failedAt = max(episode.failedAt, record.occurredAt)
                } else if record.body.contains("Turn error:"),
                          let status = statusCode(in: record.body),
                          let kind = incidentKind(for: status) {
                    episode.kind = kind
                    episode.httpStatusCode = status
                    episode.failedAt = max(episode.failedAt, record.occurredAt)
                }
            default:
                break
            }
            episodes[key] = episode
        }

        var latestByThread: [String: ServiceIncident] = [:]
        for (key, episode) in episodes {
            guard let incident = episode.incident(episodeID: key.episodeID) else {
                continue
            }
            if let current = latestByThread[key.threadID], current.occurredAt >= incident.occurredAt {
                continue
            }
            latestByThread[key.threadID] = incident
        }
        return latestByThread
    }

    private func recordPrecedes(_ lhs: LogEventRecord, _ rhs: LogEventRecord) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }
        return lhs.target < rhs.target
    }

    private func statusCode(in body: String) -> Int? {
        firstCapture(in: body, patterns: [#"status[=: ]+(\d{3})\b"#]).flatMap(Int.init)
    }

    private func incidentKind(for statusCode: Int) -> ServiceIncidentKind? {
        switch statusCode {
        case 400: .badRequest
        case 429: .httpRateLimit
        case 503: .serviceUnavailable
        case 400...599: .httpStatus(statusCode)
        default: nil
        }
    }

    private func retryProgress(in body: String) -> (attempt: Int, limit: Int)? {
        guard let values = captures(in: body, pattern: #"\((\d+)/(\d+) in "#),
              values.count == 2,
              let attempt = Int(values[0]),
              let limit = Int(values[1]),
              attempt > 0,
              limit > 0,
              attempt <= limit else {
            return nil
        }
        return (attempt, limit)
    }

    private func firstCapture(in value: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let value = captures(in: value, pattern: pattern)?.first {
                return value
            }
        }
        return nil
    }

    private func captures(in value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else {
                return nil
            }
            return String(value[range])
        }
    }
}

private struct EpisodeKey: Hashable {
    let threadID: String
    let episodeID: String
}

private struct Episode {
    var kind: ServiceIncidentKind = .serviceUnavailable
    var httpStatusCode: Int?
    var retryAttempt: Int?
    var retryLimit: Int?
    var latestErrorAt: Date?
    var latestRetryAt: Date?
    var latestSuccessAt: Date?
    var failedAt: Date?

    func incident(episodeID: String) -> ServiceIncident? {
        if let failedAt {
            return ServiceIncident(
                episodeID: episodeID,
                phase: .failed,
                kind: kind,
                httpStatusCode: httpStatusCode,
                retryAttempt: retryAttempt,
                retryLimit: retryLimit,
                occurredAt: failedAt
            )
        }

        let warningAt = [latestErrorAt, latestRetryAt].compactMap { $0 }.max()
        guard let warningAt,
              warningAt > (latestSuccessAt ?? .distantPast) else {
            return nil
        }
        return ServiceIncident(
            episodeID: episodeID,
            phase: .retrying,
            kind: kind,
            httpStatusCode: httpStatusCode,
            retryAttempt: retryAttempt,
            retryLimit: retryLimit,
            occurredAt: warningAt
        )
    }
}

private func max(_ lhs: Date?, _ rhs: Date) -> Date {
    Swift.max(lhs ?? .distantPast, rhs)
}
