public extension ThreadDisplayStatus {
    var colorBlindSafeSymbolName: String {
        switch self {
        case .error:
            "xmark.octagon.fill"
        case .needsAction:
            "exclamationmark.square.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .interrupted:
            "stop.circle.fill"
        case .running:
            "play.circle.fill"
        case .justCompleted:
            "checkmark.circle.fill"
        case .idle:
            "minus.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }
}
