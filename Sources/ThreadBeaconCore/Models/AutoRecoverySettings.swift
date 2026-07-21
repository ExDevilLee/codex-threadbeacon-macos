import Foundation

public enum AutoRecoveryIncidentType: String, Codable, CaseIterable, Sendable {
    case http400
    case http429
    case http503
    case otherHTTP
    case modelCapacity

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
        }
    }

    public var defaultRule: AutoRecoveryRule {
        switch self {
        case .http400:
            AutoRecoveryRule(
                isEnabled: true,
                prompt: "刚才请求异常中断了，请继续未完成的任务"
            )
        case .http429:
            AutoRecoveryRule(
                isEnabled: true,
                prompt: "刚才请求频率受限并已中断，请继续未完成的任务"
            )
        case .http503:
            AutoRecoveryRule(
                isEnabled: false,
                prompt: "刚才服务暂时不可用并已中断，请继续未完成的任务"
            )
        case .otherHTTP:
            AutoRecoveryRule(
                isEnabled: true,
                prompt: "刚才请求异常中断了，请继续未完成的任务"
            )
        case .modelCapacity:
            AutoRecoveryRule(
                isEnabled: true,
                prompt: "刚才因模型容量限制中断了，请继续未完成的任务"
            )
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

    public init(isEnabled: Bool, prompt: String) {
        self.isEnabled = isEnabled
        self.prompt = prompt
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
    public static let currentVersion = 1

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
        normalizeRules()
    }

    public static var defaultValue: AutoRecoverySettings {
        AutoRecoverySettings(
            isEnabled: false,
            rules: Dictionary(uniqueKeysWithValues: AutoRecoveryIncidentType.allCases.map {
                ($0, $0.defaultRule)
            })
        )
    }

    public func rule(for type: AutoRecoveryIncidentType) -> AutoRecoveryRule {
        rules[type] ?? type.defaultRule
    }

    public mutating func setRule(_ rule: AutoRecoveryRule, for type: AutoRecoveryIncidentType) {
        switch AutoRecoveryPromptValidation.validate(rule.prompt) {
        case let .valid(prompt):
            rules[type] = AutoRecoveryRule(isEnabled: rule.isEnabled, prompt: prompt)
        case .empty, .tooLong:
            rules[type] = type.defaultRule
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case isEnabled
        case rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let storedRules = try container.decodeIfPresent(
            [String: AutoRecoveryRule].self,
            forKey: .rules
        ) ?? [:]
        rules = Dictionary(uniqueKeysWithValues: storedRules.compactMap { key, value in
            AutoRecoveryIncidentType(rawValue: key).map { ($0, value) }
        })
        normalizeRules()
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

    private mutating func normalizeRules() {
        version = Self.currentVersion
        for type in AutoRecoveryIncidentType.allCases {
            let savedRule = rules[type] ?? type.defaultRule
            switch AutoRecoveryPromptValidation.validate(savedRule.prompt) {
            case let .valid(prompt):
                rules[type] = AutoRecoveryRule(
                    isEnabled: savedRule.isEnabled,
                    prompt: prompt
                )
            case .empty, .tooLong:
                rules[type] = type.defaultRule
            }
        }
    }
}
