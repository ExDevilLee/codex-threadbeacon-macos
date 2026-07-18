public struct ArchiveRestoreAvailability: Equatable, Sendable {
    public static let current = ArchiveRestoreAvailability(
        isEnabled: false,
        blockedReason: "Codex App 当前无法可靠地把恢复后的旧会话重新加入侧边栏并打开。"
    )

    public let isEnabled: Bool
    public let blockedReason: String

    public init(isEnabled: Bool, blockedReason: String) {
        self.isEnabled = isEnabled
        self.blockedReason = blockedReason
    }
}
