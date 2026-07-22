import Foundation

private enum TurnLifecycle: String, Codable {
    case unknown
    case running
    case completed
    case interrupted
}

private struct ProbeResult: Codable, Equatable {
    let lifecycle: TurnLifecycle
    let pendingUserInputCandidate: Bool
    let explicitApprovalEvidenceAvailable: Bool
}

private struct AttentionStateParser {
    func parse(lines: [String]) -> ProbeResult {
        var lifecycle: TurnLifecycle = .unknown
        var pendingUserInputCallIDs: Set<String> = []

        for line in lines {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? String,
                let payload = object["payload"] as? [String: Any]
            else {
                continue
            }

            if type == "event_msg", let eventType = payload["type"] as? String {
                switch eventType {
                case "task_started":
                    lifecycle = .running
                    pendingUserInputCallIDs.removeAll()
                case "task_complete":
                    lifecycle = .completed
                    pendingUserInputCallIDs.removeAll()
                case "turn_aborted":
                    lifecycle = .interrupted
                    pendingUserInputCallIDs.removeAll()
                default:
                    break
                }
                continue
            }

            guard type == "response_item" else { continue }
            let itemType = payload["type"] as? String
            if itemType == "function_call",
               payload["name"] as? String == "request_user_input",
               let callID = payload["call_id"] as? String,
               !callID.isEmpty {
                pendingUserInputCallIDs.insert(callID)
            } else if itemType == "function_call_output" || itemType == "custom_tool_call_output",
                      let callID = payload["call_id"] as? String {
                pendingUserInputCallIDs.remove(callID)
            }
        }

        return ProbeResult(
            lifecycle: lifecycle,
            pendingUserInputCandidate: lifecycle == .running && !pendingUserInputCallIDs.isEmpty,
            explicitApprovalEvidenceAvailable: false
        )
    }
}

private func readTail(of url: URL, maximumBytes: UInt64 = 2 * 1024 * 1024) throws -> [String] {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    let size = try handle.seekToEnd()
    let start = size > maximumBytes ? size - maximumBytes : 0
    try handle.seek(toOffset: start)
    var data = try handle.readToEnd() ?? Data()
    if start > 0, let newline = data.firstIndex(of: 0x0A) {
        data.removeSubrange(data.startIndex...newline)
    }
    return String(decoding: data, as: UTF8.self)
        .split(whereSeparator: \ .isNewline)
        .map(String.init)
}

private func encode(_ result: ProbeResult) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(result), as: UTF8.self)
}

private func runSelfTest() throws {
    let parser = AttentionStateParser()
    let started = #"{"timestamp":"2026-07-22T01:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#
    let request = #"{"timestamp":"2026-07-22T01:00:01Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"call-1","arguments":"{}"}}"#
    let output = #"{"timestamp":"2026-07-22T01:00:02Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-1","output":"{}"}}"#
    let completed = #"{"timestamp":"2026-07-22T01:00:03Z","type":"event_msg","payload":{"type":"task_complete"}}"#
    let aborted = #"{"timestamp":"2026-07-22T01:00:03Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#

    precondition(
        parser.parse(lines: [started, request])
            == ProbeResult(
                lifecycle: .running,
                pendingUserInputCandidate: true,
                explicitApprovalEvidenceAvailable: false
            )
    )
    precondition(
        parser.parse(lines: [started, request, output, completed])
            == ProbeResult(
                lifecycle: .completed,
                pendingUserInputCandidate: false,
                explicitApprovalEvidenceAvailable: false
            )
    )
    precondition(
        parser.parse(lines: [started, request, aborted])
            == ProbeResult(
                lifecycle: .interrupted,
                pendingUserInputCandidate: false,
                explicitApprovalEvidenceAvailable: false
            )
    )
    print("AttentionStateProbe self-test passed")
}

private func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try runSelfTest()
        return
    }
    guard arguments.count == 2, arguments[0] == "--rollout" else {
        throw NSError(
            domain: "AttentionStateProbe",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Usage: swift Tools/AttentionStateProbe/main.swift --rollout <path> | --self-test"
            ]
        )
    }

    let result = AttentionStateParser().parse(
        lines: try readTail(of: URL(fileURLWithPath: arguments[1]))
    )
    print(try encode(result))
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
