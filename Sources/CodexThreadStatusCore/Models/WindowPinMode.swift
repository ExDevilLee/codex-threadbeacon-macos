public enum WindowPinMode: Equatable, Sendable {
    case normal
    case floating

    public init(isPinned: Bool) {
        self = isPinned ? .floating : .normal
    }
}
