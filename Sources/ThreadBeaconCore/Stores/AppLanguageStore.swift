import Combine
import Foundation

@MainActor
public final class AppLanguageStore: ObservableObject {
    @Published public private(set) var rawValue: String

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: DisplayPreferenceKeys.appLanguage)
        let language = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .defaultValue
        rawValue = language.rawValue
        if storedValue != rawValue {
            defaults.set(rawValue, forKey: DisplayPreferenceKeys.appLanguage)
        }
    }

    public var language: AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .system
    }

    public var locale: Locale {
        language.resolvedLocale()
    }

    public func setLanguage(_ language: AppLanguage) {
        let newValue = language.rawValue
        guard rawValue != newValue else { return }
        rawValue = newValue
        defaults.set(newValue, forKey: DisplayPreferenceKeys.appLanguage)
    }
}
