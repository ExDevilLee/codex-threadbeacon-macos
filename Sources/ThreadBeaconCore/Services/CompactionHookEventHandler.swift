import Foundation

public enum CompactionHookEventError: Error, Equatable, Sendable {
    case invalidPayload
    case invalidIdentifier
    case invalidTrigger
    case unsupportedEvent

    public var diagnosticCode: String {
        switch self {
        case .invalidPayload: "invalid_payload"
        case .invalidIdentifier: "invalid_identifier"
        case .invalidTrigger: "invalid_trigger"
        case .unsupportedEvent: "unsupported_event"
        }
    }
}

public struct CompactionHookEventHandler: Sendable {
    private let repository: CompactionActivityRepository
    private let now: @Sendable () -> Date

    public init(
        repository: CompactionActivityRepository = CompactionActivityRepository(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.now = now
    }

    public func handle(data: Data) throws {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let eventName = object["hook_event_name"] as? String,
            let rawSessionID = object["session_id"] as? String,
            let rawTurnID = object["turn_id"] as? String,
            let rawTrigger = object["trigger"] as? String
        else {
            throw CompactionHookEventError.invalidPayload
        }
        guard
            let sessionID = UUID(uuidString: rawSessionID)?.uuidString.lowercased(),
            let turnID = UUID(uuidString: rawTurnID)?.uuidString.lowercased()
        else {
            throw CompactionHookEventError.invalidIdentifier
        }
        guard let trigger = CompactionTrigger(rawValue: rawTrigger) else {
            throw CompactionHookEventError.invalidTrigger
        }

        switch eventName {
        case "PreCompact":
            try repository.write(CompactionActivity(
                sessionID: sessionID,
                turnID: turnID,
                trigger: trigger,
                startedAt: now()
            ))
        case "PostCompact":
            try repository.clear(sessionID: sessionID, turnID: turnID)
        default:
            throw CompactionHookEventError.unsupportedEvent
        }
    }
}
