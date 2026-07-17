import Foundation

public enum SubagentAliasFormatter {
    public static func displayAlias(nickname: String?, title: String) -> String? {
        guard let nickname else {
            return nil
        }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != title else {
            return nil
        }
        return trimmed
    }
}
