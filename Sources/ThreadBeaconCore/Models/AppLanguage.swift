import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let defaultValue: AppLanguage = .system

    public func resolvedLocaleIdentifier(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .simplifiedChinese:
            return AppLanguage.simplifiedChinese.rawValue
        case .english:
            return AppLanguage.english.rawValue
        case .system:
            guard let preferredLanguage = preferredLanguages.first?.lowercased() else {
                return AppLanguage.english.rawValue
            }
            return preferredLanguage.hasPrefix("zh")
                ? AppLanguage.simplifiedChinese.rawValue
                : AppLanguage.english.rawValue
        }
    }

    public func resolvedLocale(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Locale {
        Locale(identifier: resolvedLocaleIdentifier(preferredLanguages: preferredLanguages))
    }
}
