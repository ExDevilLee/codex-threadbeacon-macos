import Foundation

public struct AccessibilityButtonDescriptor: Equatable, Sendable {
    public let role: String
    public let actionNames: [String]
    public let domClassNames: [String]
    public let isEnabled: Bool

    public init(
        role: String,
        actionNames: [String],
        domClassNames: [String],
        isEnabled: Bool = true
    ) {
        self.role = role
        self.actionNames = actionNames
        self.domClassNames = domClassNames
        self.isEnabled = isEnabled
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
        }
    }

    public static func uniqueCandidateIndex(
        in descriptors: [AccessibilityButtonDescriptor]
    ) -> Int? {
        let matches = candidateIndices(in: descriptors)
        return matches.count == 1 ? matches[0] : nil
    }
}
