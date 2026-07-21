public enum TaskOpenRequestDecision: Equatable, Sendable {
    case allowed
    case archived
    case notAuthorized
    case interactionInProgress
}

public enum TaskOpenRequestPolicy {
    public static func evaluate(
        isArchived: Bool,
        isAuthorized: Bool,
        isInteractionInProgress: Bool
    ) -> TaskOpenRequestDecision {
        if isArchived { return .archived }
        if !isAuthorized { return .notAuthorized }
        if isInteractionInProgress { return .interactionInProgress }
        return .allowed
    }
}

public enum TaskOpenResult: Equatable, Sendable {
    case opened
    case archived
    case notAuthorized
    case interactionInProgress
    case selectionFailed(AccessibilityTargetSelectionResult)

    public var isOpened: Bool {
        self == .opened
    }

    public var shouldPresentFailure: Bool {
        !isOpened
    }

    public var shouldOfferAccessibilitySettings: Bool {
        self == .notAuthorized
    }
}
