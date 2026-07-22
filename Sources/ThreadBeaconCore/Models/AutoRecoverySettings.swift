import Foundation

public enum AutoRecoveryPromptLanguage: String, Codable, Sendable {
    case simplifiedChinese
    case english

    public init(localeIdentifier: String) {
        self = localeIdentifier.lowercased().hasPrefix("zh")
            ? .simplifiedChinese
            : .english
    }
}

public enum AutoRecoveryPromptSource: String, Codable, Sendable {
    case defaultValue
    case custom
}

public enum AutoRecoveryIncidentType: String, Codable, CaseIterable, Sendable {
    case http400
    case http429
    case http503
    case otherHTTP
    case modelCapacity
    case streamDisconnected

    public init(incidentKind: ServiceIncidentKind) {
        switch incidentKind {
        case .badRequest:
            self = .http400
        case .httpRateLimit:
            self = .http429
        case .serviceUnavailable:
            self = .http503
        case .httpStatus:
            self = .otherHTTP
        case .modelCapacity:
            self = .modelCapacity
        case .streamDisconnected:
            self = .streamDisconnected
        }
    }

    public var defaultRule: AutoRecoveryRule {
        defaultRule(promptLanguage: .simplifiedChinese)
    }

    public func defaultRule(
        promptLanguage: AutoRecoveryPromptLanguage
    ) -> AutoRecoveryRule {
        AutoRecoveryRule(
            isEnabled: defaultIsEnabled,
            prompt: defaultPrompt(promptLanguage: promptLanguage),
            promptSource: .defaultValue
        )
    }

    fileprivate func isLegacyDefaultPrompt(_ prompt: String) -> Bool {
        prompt == defaultPrompt(promptLanguage: .simplifiedChinese)
    }

    private func defaultPrompt(
        promptLanguage: AutoRecoveryPromptLanguage
    ) -> String {
        switch promptLanguage {
        case .simplifiedChinese:
            switch self {
            case .http400:
                "刚才请求异常中断了，请继续未完成的任务"
            case .http429:
                "刚才请求频率受限并已中断，请继续未完成的任务"
            case .http503:
                "刚才服务暂时不可用并已中断，请继续未完成的任务"
            case .otherHTTP:
                "刚才请求异常中断了，请继续未完成的任务"
            case .modelCapacity:
                "刚才因模型容量限制中断了，请继续未完成的任务"
            case .streamDisconnected:
                "刚才连接中断且重试失败，请继续未完成的任务"
            }
        case .english:
            switch self {
            case .http400:
                "The previous request was interrupted by an error. Please continue the unfinished task."
            case .http429:
                "The previous request was interrupted by rate limiting. Please continue the unfinished task."
            case .http503:
                "The previous request was interrupted because the service was unavailable. Please continue the unfinished task."
            case .otherHTTP:
                "The previous request was interrupted by an HTTP error. Please continue the unfinished task."
            case .modelCapacity:
                "The previous request was interrupted due to model capacity limits. Please continue the unfinished task."
            case .streamDisconnected:
                "The connection was interrupted and all retries failed. Please continue the unfinished task."
            }
        }
    }

    private var defaultIsEnabled: Bool {
        switch self {
        case .http503:
            false
        case .http400, .http429, .otherHTTP, .modelCapacity, .streamDisconnected:
            true
        }
    }
}

public struct AutoRecoveryCandidate: Equatable, Sendable {
    public let threadID: String
    public let episodeID: String
    public let incidentType: AutoRecoveryIncidentType
    public let incidentLabel: String

    public init(
        threadID: String,
        episodeID: String,
        incidentType: AutoRecoveryIncidentType,
        incidentLabel: String
    ) {
        self.threadID = threadID
        self.episodeID = episodeID
        self.incidentType = incidentType
        self.incidentLabel = incidentLabel
    }
}

public enum AutoRecoveryDecision: Equatable, Sendable {
    case disabled
    case needsAccessibilityAuthorization(prompt: String)
    case send(prompt: String)
}

public enum AutoRecoveryPolicy {
    public static func evaluate(
        candidate: AutoRecoveryCandidate,
        settings: AutoRecoverySettings,
        isAccessibilityAuthorized: Bool
    ) -> AutoRecoveryDecision {
        guard settings.isEnabled else { return .disabled }
        let rule = settings.rule(for: candidate.incidentType)
        guard rule.isEnabled else { return .disabled }
        guard isAccessibilityAuthorized else {
            return .needsAccessibilityAuthorization(prompt: rule.prompt)
        }
        return .send(prompt: rule.prompt)
    }
}

public struct AutoRecoveryRule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var prompt: String
    public var promptSource: AutoRecoveryPromptSource

    public init(
        isEnabled: Bool,
        prompt: String,
        promptSource: AutoRecoveryPromptSource = .custom
    ) {
        self.isEnabled = isEnabled
        self.prompt = prompt
        self.promptSource = promptSource
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case prompt
        case promptSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        prompt = try container.decode(String.self, forKey: .prompt)
        promptSource = try container.decodeIfPresent(
            AutoRecoveryPromptSource.self,
            forKey: .promptSource
        ) ?? .custom
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(promptSource, forKey: .promptSource)
    }
}

public enum AutoRecoveryPromptValidation: Equatable, Sendable {
    public static let maximumCharacterCount = 500

    case valid(String)
    case empty
    case tooLong

    public static func validate(_ prompt: String) -> AutoRecoveryPromptValidation {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .empty }
        guard normalized.count <= maximumCharacterCount else { return .tooLong }
        return .valid(normalized)
    }
}

public struct AutoRecoverySettings: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var isEnabled: Bool
    private var rules: [AutoRecoveryIncidentType: AutoRecoveryRule]

    public init(
        version: Int = AutoRecoverySettings.currentVersion,
        isEnabled: Bool,
        rules: [AutoRecoveryIncidentType: AutoRecoveryRule]
    ) {
        self.version = version
        self.isEnabled = isEnabled
        self.rules = rules
        normalizeRules(sourceVersion: version)
    }

    public static var defaultValue: AutoRecoverySettings {
        defaultValue(promptLanguage: .simplifiedChinese)
    }

    public static func defaultValue(
        promptLanguage: AutoRecoveryPromptLanguage
    ) -> AutoRecoverySettings {
        AutoRecoverySettings(
            isEnabled: false,
            rules: Dictionary(uniqueKeysWithValues: AutoRecoveryIncidentType.allCases.map {
                ($0, $0.defaultRule(promptLanguage: promptLanguage))
            })
        )
    }

    public func rule(for type: AutoRecoveryIncidentType) -> AutoRecoveryRule {
        rules[type] ?? type.defaultRule
    }

    public mutating func setRule(_ rule: AutoRecoveryRule, for type: AutoRecoveryIncidentType) {
        switch AutoRecoveryPromptValidation.validate(rule.prompt) {
        case let .valid(prompt):
            rules[type] = AutoRecoveryRule(
                isEnabled: rule.isEnabled,
                prompt: prompt,
                promptSource: rule.promptSource
            )
        case .empty, .tooLong:
            rules[type] = type.defaultRule
        }
    }

    public mutating func synchronizeDefaultPrompts(
        to promptLanguage: AutoRecoveryPromptLanguage
    ) {
        for type in AutoRecoveryIncidentType.allCases {
            let currentRule = rule(for: type)
            guard currentRule.promptSource == .defaultValue else { continue }
            let localizedDefault = type.defaultRule(promptLanguage: promptLanguage)
            rules[type] = AutoRecoveryRule(
                isEnabled: currentRule.isEnabled,
                prompt: localizedDefault.prompt,
                promptSource: .defaultValue
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case isEnabled
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        version = storedVersion
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let storedRules = try container.decodeIfPresent(
            [String: AutoRecoveryRule].self,
            forKey: .rules
        ) ?? [:]
        rules = Dictionary(uniqueKeysWithValues: storedRules.compactMap { key, value in
            AutoRecoveryIncidentType(rawValue: key).map { ($0, value) }
        })
        normalizeRules(sourceVersion: storedVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(
            Dictionary(uniqueKeysWithValues: rules.map { ($0.key.rawValue, $0.value) }),
            forKey: .rules
        )
    }

    private mutating func normalizeRules(sourceVersion: Int) {
        version = Self.currentVersion
        for type in AutoRecoveryIncidentType.allCases {
            let savedRule = rules[type] ?? type.defaultRule
            switch AutoRecoveryPromptValidation.validate(savedRule.prompt) {
            case let .valid(prompt):
                let promptSource = sourceVersion < Self.currentVersion
                    ? (type.isLegacyDefaultPrompt(prompt) ? .defaultValue : .custom)
                    : savedRule.promptSource
                rules[type] = AutoRecoveryRule(
                    isEnabled: savedRule.isEnabled,
                    prompt: prompt,
                    promptSource: promptSource
                )
            case .empty, .tooLong:
                rules[type] = type.defaultRule
            }
        }
    }
}
