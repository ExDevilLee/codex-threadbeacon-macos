import Foundation

public enum SubagentAliasFormatter {
    public static func displayAlias(
        agentPath: String?,
        nickname: String?,
        title: String
    ) -> String? {
        let candidate = semanticTaskName(from: agentPath) ?? normalized(nickname)
        guard let candidate, candidate != title else {
            return nil
        }
        return candidate
    }

    public static func displayAlias(nickname: String?, title: String) -> String? {
        displayAlias(agentPath: nil, nickname: nickname, title: title)
    }

    private static func semanticTaskName(from agentPath: String?) -> String? {
        guard let path = normalized(agentPath),
              let component = path.split(separator: "/").last else {
            return nil
        }
        let words = component
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map(String.init)
            .joined(separator: " ")
        guard !words.isEmpty else {
            return nil
        }
        return String(words.prefix(1)).uppercased() + words.dropFirst()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
