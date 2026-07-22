import Foundation

public struct AccessibilityButtonDescriptor: Equatable, Sendable {
    public let role: String
    public let actionNames: [String]
    public let domClassNames: [String]
    public let isEnabled: Bool
    public let title: String
    public let description: String

    public init(
        role: String,
        actionNames: [String],
        domClassNames: [String],
        isEnabled: Bool = true,
        title: String = "",
        description: String = ""
    ) {
        self.role = role
        self.actionNames = actionNames
        self.domClassNames = domClassNames
        self.isEnabled = isEnabled
        self.title = title
        self.description = description
    }
}

public enum AccessibilitySendButtonPolicy {
    public static func candidateIndices(
        in descriptors: [AccessibilityButtonDescriptor]
    ) -> [Int] {
        descriptors.indices.filter { index in
            let descriptor = descriptors[index]
            return descriptor.isEnabled
                && descriptor.role == "AXButton"
                && descriptor.actionNames.contains("AXPress")
                && descriptor.domClassNames.contains("size-token-button-composer")
                && descriptor.domClassNames.contains("bg-token-foreground")
                && hasSendSemantic(descriptor)
        }
    }

    public static func uniqueCandidateIndex(
        in descriptors: [AccessibilityButtonDescriptor]
    ) -> Int? {
        let matches = candidateIndices(in: descriptors)
        return matches.count == 1 ? matches[0] : nil
    }

    private static func hasSendSemantic(_ descriptor: AccessibilityButtonDescriptor) -> Bool {
        let semanticText = [descriptor.title, descriptor.description]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if semanticText.isEmpty { return true }
        return ["send", "submit", "发送", "提交"].contains { semanticText.contains($0) }
    }
}
