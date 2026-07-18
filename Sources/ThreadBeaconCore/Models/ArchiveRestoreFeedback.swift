public enum ArchiveRestoreFeedback: Equatable, Sendable {
    case success(threadID: String)
    case failure(threadID: String, message: String)
}
