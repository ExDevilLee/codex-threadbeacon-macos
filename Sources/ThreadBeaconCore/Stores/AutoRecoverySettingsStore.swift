import Combine
import Foundation

public struct AutoRecoverySettingsRepository {
    public static let storageKey = "autoRecoverySettings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AutoRecoverySettings {
        guard let value = defaults.string(forKey: Self.storageKey),
              let data = value.data(using: .utf8),
              let settings = try? JSONDecoder().decode(AutoRecoverySettings.self, from: data) else {
            return .defaultValue
        }
        return settings
    }

    public func save(_ settings: AutoRecoverySettings) {
        guard let data = try? JSONEncoder().encode(settings),
              let value = String(data: data, encoding: .utf8) else {
            return
        }
        defaults.set(value, forKey: Self.storageKey)
    }
}

@MainActor
public final class AutoRecoverySettingsStore: ObservableObject {
    @Published public private(set) var settings: AutoRecoverySettings

    private let repository: AutoRecoverySettingsRepository

    public init(repository: AutoRecoverySettingsRepository = AutoRecoverySettingsRepository()) {
        self.repository = repository
        settings = repository.load()
    }

    public func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        repository.save(settings)
    }

    @discardableResult
    public func updateRule(
        for type: AutoRecoveryIncidentType,
        isEnabled: Bool,
        prompt: String
    ) -> AutoRecoveryPromptValidation {
        let validation = AutoRecoveryPromptValidation.validate(prompt)
        guard case let .valid(normalizedPrompt) = validation else { return validation }
        settings.setRule(
            AutoRecoveryRule(isEnabled: isEnabled, prompt: normalizedPrompt),
            for: type
        )
        repository.save(settings)
        return validation
    }

    public func resetRule(for type: AutoRecoveryIncidentType) {
        settings.setRule(type.defaultRule, for: type)
        repository.save(settings)
    }
}
