import Foundation
import ThreadBeaconCore

let autoRecoverySettingsTests = [
    TestCase(name: "auto recovery defaults stay globally disabled and keep 503 off") {
        let settings = AutoRecoverySettings.defaultValue

        try expect(!settings.isEnabled, "automatic recovery must require explicit opt in")
        try expect(settings.rule(for: .http400).isEnabled, "HTTP 400 should be ready when opted in")
        try expect(settings.rule(for: .http429).isEnabled, "HTTP 429 should be ready when opted in")
        try expect(!settings.rule(for: .http503).isEnabled, "HTTP 503 should default off")
        try expect(settings.rule(for: .otherHTTP).isEnabled, "other HTTP failures should default on")
        try expect(settings.rule(for: .modelCapacity).isEnabled, "capacity failures should default on")
        try expect(
            AutoRecoveryIncidentType.allCases.allSatisfy {
                !settings.rule(for: $0).prompt.isEmpty
            },
            "every supported incident should have a default prompt"
        )
    },
    TestCase(name: "auto recovery prompt validation trims valid text and rejects invalid text") {
        try expect(
            AutoRecoveryPromptValidation.validate("  继续未完成任务  ") == .valid("继续未完成任务"),
            "valid prompts should be trimmed"
        )
        try expect(
            AutoRecoveryPromptValidation.validate("  \n ") == .empty,
            "blank prompts should be rejected"
        )
        try expect(
            AutoRecoveryPromptValidation.validate(String(repeating: "a", count: 501)) == .tooLong,
            "prompts longer than 500 characters should be rejected"
        )
    },
    TestCase(name: "auto recovery settings repository persists and reloads rules") {
        let suiteName = "AutoRecoverySettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = AutoRecoverySettingsRepository(defaults: defaults)
        var settings = AutoRecoverySettings.defaultValue
        settings.isEnabled = true
        settings.setRule(
            AutoRecoveryRule(isEnabled: true, prompt: "429 custom prompt"),
            for: .http429
        )
        settings.setRule(
            AutoRecoveryRule(isEnabled: true, prompt: "503 custom prompt"),
            for: .http503
        )

        repository.save(settings)
        let loaded = repository.load()

        try expect(loaded.isEnabled, "global enabled state should persist")
        try expect(loaded.rule(for: .http429).prompt == "429 custom prompt", "custom prompt should persist")
        try expect(loaded.rule(for: .http503).isEnabled, "503 opt in should persist")
    },
    TestCase(name: "auto recovery settings repository fills missing rules") {
        let suiteName = "AutoRecoverySettingsTests.partial.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            #"{"version":1,"isEnabled":true,"rules":{"http400":{"isEnabled":false,"prompt":"custom 400"}}}"#,
            forKey: AutoRecoverySettingsRepository.storageKey
        )

        let loaded = AutoRecoverySettingsRepository(defaults: defaults).load()

        try expect(loaded.isEnabled, "valid global state should survive partial migration")
        try expect(!loaded.rule(for: .http400).isEnabled, "saved rule should survive migration")
        try expect(loaded.rule(for: .http400).prompt == "custom 400", "saved prompt should survive migration")
        try expect(!loaded.rule(for: .http503).isEnabled, "missing 503 rule should use its default")
        try expect(loaded.rule(for: .modelCapacity).isEnabled, "missing capacity rule should use its default")
    },
    TestCase(name: "auto recovery settings repository fails closed on corrupt data") {
        let suiteName = "AutoRecoverySettingsTests.corrupt.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("not-json", forKey: AutoRecoverySettingsRepository.storageKey)

        let loaded = AutoRecoverySettingsRepository(defaults: defaults).load()

        try expect(loaded == .defaultValue, "corrupt data should restore safe defaults")
        try expect(!loaded.isEnabled, "corrupt data must not enable automatic recovery")
    },
    TestCase(name: "service incidents map to stable auto recovery types") {
        let cases: [(ServiceIncidentKind, AutoRecoveryIncidentType)] = [
            (.badRequest, .http400),
            (.httpRateLimit, .http429),
            (.serviceUnavailable, .http503),
            (.httpStatus(401), .otherHTTP),
            (.httpStatus(500), .otherHTTP),
            (.modelCapacity, .modelCapacity)
        ]

        for (kind, expectedType) in cases {
            try expect(
                AutoRecoveryIncidentType(incidentKind: kind) == expectedType,
                "\(kind) should map to \(expectedType)"
            )
        }
    },
    TestCase(name: "auto recovery policy stays silent when global recovery is disabled") {
        let candidate = recoveryCandidate(type: .http400)

        let decision = AutoRecoveryPolicy.evaluate(
            candidate: candidate,
            settings: .defaultValue,
            isAccessibilityAuthorized: true
        )

        try expect(decision == .disabled, "global opt in should be required")
    },
    TestCase(name: "auto recovery policy keeps HTTP 503 disabled by default") {
        var settings = AutoRecoverySettings.defaultValue
        settings.isEnabled = true

        let decision = AutoRecoveryPolicy.evaluate(
            candidate: recoveryCandidate(type: .http503),
            settings: settings,
            isAccessibilityAuthorized: true
        )

        try expect(decision == .disabled, "HTTP 503 should require an explicit per-type opt in")
    },
    TestCase(name: "auto recovery policy requests authorization with the configured prompt") {
        var settings = AutoRecoverySettings.defaultValue
        settings.isEnabled = true
        settings.setRule(
            AutoRecoveryRule(isEnabled: true, prompt: "custom recovery"),
            for: .http400
        )

        let decision = AutoRecoveryPolicy.evaluate(
            candidate: recoveryCandidate(type: .http400),
            settings: settings,
            isAccessibilityAuthorized: false
        )

        try expect(
            decision == .needsAccessibilityAuthorization(prompt: "custom recovery"),
            "enabled recovery without permission should be logged as authorization-required"
        )
    },
    TestCase(name: "auto recovery policy sends the configured prompt when authorized") {
        var settings = AutoRecoverySettings.defaultValue
        settings.isEnabled = true
        settings.setRule(
            AutoRecoveryRule(isEnabled: true, prompt: "continue this task"),
            for: .http429
        )

        let decision = AutoRecoveryPolicy.evaluate(
            candidate: recoveryCandidate(type: .http429),
            settings: settings,
            isAccessibilityAuthorized: true
        )

        try expect(
            decision == .send(prompt: "continue this task"),
            "authorized recovery should carry the configured prompt into the sender"
        )
    }
]

private func recoveryCandidate(type: AutoRecoveryIncidentType) -> AutoRecoveryCandidate {
    AutoRecoveryCandidate(
        threadID: "thread-id",
        episodeID: "episode-id",
        incidentType: type,
        incidentLabel: type.rawValue
    )
}
