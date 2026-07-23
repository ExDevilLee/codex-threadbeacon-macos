import Combine
import Foundation

public struct AutoRecoverySettingsRepository {
    public static let storageKey = "autoRecoverySettings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(
        promptLanguage: AutoRecoveryPromptLanguage = .simplifiedChinese
    ) -> AutoRecoverySettings {
        guard let value = defaults.string(forKey: Self.storageKey),
              let data = value.data(using: .utf8),
              var settings = try? JSONDecoder().decode(AutoRecoverySettings.self, from: data) else {
            return .defaultValue(promptLanguage: promptLanguage)
        }
        settings.synchronizeDefaultPrompts(to: promptLanguage)
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
    private var promptLanguage: AutoRecoveryPromptLanguage

    public init(
        repository: AutoRecoverySettingsRepository = AutoRecoverySettingsRepository(),
        promptLanguage: AutoRecoveryPromptLanguage = .simplifiedChinese
    ) {
        self.repository = repository
        self.promptLanguage = promptLanguage
        settings = repository.load(promptLanguage: promptLanguage)
        repository.save(settings)
    }

    public func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        repository.save(settings)
    }

    public func setPromptLanguage(_ promptLanguage: AutoRecoveryPromptLanguage) {
        guard self.promptLanguage != promptLanguage else { return }
        self.promptLanguage = promptLanguage
        settings.synchronizeDefaultPrompts(to: promptLanguage)
        repository.save(settings)
    }

    public func setRuleEnabled(
        _ isEnabled: Bool,
        for type: AutoRecoveryIncidentType
    ) {
        var rule = settings.rule(for: type)
        guard rule.isEnabled != isEnabled else { return }
        rule.isEnabled = isEnabled
        settings.setRule(rule, for: type)
        repository.save(settings)
    }

    public func setCircuitBreakerEnabled(
        _ isEnabled: Bool,
        for type: AutoRecoveryIncidentType
    ) {
        var rule = settings.rule(for: type)
        guard rule.isCircuitBreakerEnabled != isEnabled else { return }
        rule.isCircuitBreakerEnabled = isEnabled
        settings.setRule(rule, for: type)
        repository.save(settings)
    }

    public func setMaximumConsecutiveAttempts(
        _ maximum: Int,
        for type: AutoRecoveryIncidentType
    ) {
        var rule = settings.rule(for: type)
        let normalized = AutoRecoveryRule.clampedMaximum(maximum)
        guard rule.maximumConsecutiveAttempts != normalized else { return }
        rule.maximumConsecutiveAttempts = normalized
        settings.setRule(rule, for: type)
        repository.save(settings)
    }

    @discardableResult
    public func savePrompt(
        for type: AutoRecoveryIncidentType,
        prompt: String
    ) -> AutoRecoveryPromptValidation {
        let validation = AutoRecoveryPromptValidation.validate(prompt)
        guard case let .valid(normalizedPrompt) = validation else { return validation }
        let currentRule = settings.rule(for: type)
        settings.setRule(
            AutoRecoveryRule(
                isEnabled: currentRule.isEnabled,
                prompt: normalizedPrompt,
                promptSource: .custom,
                isCircuitBreakerEnabled: currentRule.isCircuitBreakerEnabled,
                maximumConsecutiveAttempts: currentRule.maximumConsecutiveAttempts
            ),
            for: type
        )
        repository.save(settings)
        return validation
    }

    public func resetRule(for type: AutoRecoveryIncidentType) {
        let currentRule = settings.rule(for: type)
        let defaultRule = type.defaultRule(promptLanguage: promptLanguage)
        settings.setRule(
            AutoRecoveryRule(
                isEnabled: currentRule.isEnabled,
                prompt: defaultRule.prompt,
                promptSource: .defaultValue,
                isCircuitBreakerEnabled: currentRule.isCircuitBreakerEnabled,
                maximumConsecutiveAttempts: currentRule.maximumConsecutiveAttempts
            ),
            for: type
        )
        repository.save(settings)
    }
}
