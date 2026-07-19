import Foundation

public enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public static let defaultValue: AppTheme = .system
}
