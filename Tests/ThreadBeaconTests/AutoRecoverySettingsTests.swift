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
    TestCase(name: "auto recovery defaults use the selected prompt language") {
        let chinese = AutoRecoverySettings.defaultValue(
            promptLanguage: .simplifiedChinese
        )
        let english = AutoRecoverySettings.defaultValue(promptLanguage: .english)

        try expect(
            chinese.rule(for: .http400).prompt
                == "刚才请求异常中断了，请继续未完成的任务",
            "Chinese should keep the existing HTTP 400 default"
        )
        try expect(
            english.rule(for: .http400).prompt
                == "The previous request was interrupted by an error. Please continue the unfinished task.",
            "English should use the English HTTP 400 default"
        )
        try expect(
            english.rule(for: .http429).prompt
                == "The previous request was interrupted by rate limiting. Please continue the unfinished task.",
            "English should use the English HTTP 429 default"
        )
        try expect(
            english.rule(for: .http503).prompt
                == "The previous request was interrupted because the service was unavailable. Please continue the unfinished task.",
            "English should use the English HTTP 503 default"
        )
        try expect(
            english.rule(for: .otherHTTP).prompt
                == "The previous request was interrupted by an HTTP error. Please continue the unfinished task.",
            "English should use the English fallback HTTP default"
        )
        try expect(
            english.rule(for: .modelCapacity).prompt
                == "The previous request was interrupted due to model capacity limits. Please continue the unfinished task.",
            "English should use the English model-capacity default"
        )
        try expect(
            AutoRecoveryIncidentType.allCases.allSatisfy {
                english.rule(for: $0).promptSource == .defaultValue
            },
            "built-in prompts should retain default provenance"
        )
    },
    TestCase(name: "auto recovery v1 migration distinguishes defaults from custom prompts") {
        let data = Data(
            #"{"version":1,"isEnabled":true,"rules":{"http400":{"isEnabled":true,"prompt":"刚才请求异常中断了，请继续未完成的任务"},"http429":{"isEnabled":true,"prompt":"my custom retry prompt"}}}"#.utf8
        )

        let settings = try JSONDecoder().decode(AutoRecoverySettings.self, from: data)

        try expect(settings.version == 2, "v1 settings should migrate to v2")
        try expect(
            settings.rule(for: .http400).promptSource == .defaultValue,
            "an exact legacy built-in prompt should migrate as a default"
        )
        try expect(
            settings.rule(for: .http429).promptSource == .custom,
            "a non-default legacy prompt should migrate as custom"
        )
        try expect(
            settings.rule(for: .http429).prompt == "my custom retry prompt",
            "migration must preserve custom prompt text"
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
    TestCase(name: "auto recovery store localizes defaults and preserves custom prompts") {
        let suiteName = "AutoRecoverySettingsTests.language.\(UUID().uuidString)"
        let result = await MainActor.run { () -> (
            String,
            AutoRecoveryPromptSource,
            String,
            AutoRecoveryPromptSource,
            Bool,
            AutoRecoveryPromptSource,
            String,
            AutoRecoveryPromptSource
        )? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let repository = AutoRecoverySettingsRepository(defaults: defaults)
            let store = AutoRecoverySettingsStore(
                repository: repository,
                promptLanguage: .simplifiedChinese
            )

            store.setPromptLanguage(.english)
            let englishDefault = store.settings.rule(for: .http400)
            _ = store.savePrompt(for: .http429, prompt: "my custom retry prompt")
            store.setPromptLanguage(.simplifiedChinese)
            let customAfterLanguageChange = store.settings.rule(for: .http429)
            store.setRuleEnabled(false, for: .http429)
            let customAfterToggle = store.settings.rule(for: .http429)
            store.resetRule(for: .http429)
            let resetRule = store.settings.rule(for: .http429)

            return (
                englishDefault.prompt,
                englishDefault.promptSource,
                customAfterLanguageChange.prompt,
                customAfterLanguageChange.promptSource,
                customAfterToggle.isEnabled,
                customAfterToggle.promptSource,
                resetRule.prompt,
                resetRule.promptSource
            )
        }
        guard let result else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }

        try expect(
            result.0
                == "The previous request was interrupted by an error. Please continue the unfinished task.",
            "default prompts should switch to English"
        )
        try expect(result.1 == .defaultValue, "language sync should retain default provenance")
        try expect(result.2 == "my custom retry prompt", "custom text should survive language changes")
        try expect(result.3 == .custom, "saved prompts should be custom")
        try expect(!result.4, "rule enabled state should update independently")
        try expect(result.5 == .custom, "toggling a rule must preserve prompt provenance")
        try expect(
            result.6 == "刚才请求频率受限并已中断，请继续未完成的任务",
            "restore default should use the current prompt language"
        )
        try expect(result.7 == .defaultValue, "restore default should restore default provenance")
    },
    TestCase(name: "auto recovery store migrates legacy defaults using the active language") {
        let suiteName = "AutoRecoverySettingsTests.storeMigration.\(UUID().uuidString)"
        let result = await MainActor.run { () -> (AutoRecoveryRule, AutoRecoveryRule, String?)? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(
                #"{"version":1,"isEnabled":false,"rules":{"http400":{"isEnabled":true,"prompt":"刚才请求异常中断了，请继续未完成的任务"},"http429":{"isEnabled":true,"prompt":"user-authored prompt"}}}"#,
                forKey: AutoRecoverySettingsRepository.storageKey
            )
            let store = AutoRecoverySettingsStore(
                repository: AutoRecoverySettingsRepository(defaults: defaults),
                promptLanguage: .english
            )
            return (
                store.settings.rule(for: .http400),
                store.settings.rule(for: .http429),
                defaults.string(forKey: AutoRecoverySettingsRepository.storageKey)
            )
        }
        guard let result else {
            throw TestFailure(description: "could not create isolated UserDefaults suite")
        }

        try expect(
            result.0.prompt
                == "The previous request was interrupted by an error. Please continue the unfinished task.",
            "legacy defaults should migrate to the active language"
        )
        try expect(result.0.promptSource == .defaultValue, "legacy defaults should remain defaults")
        try expect(result.1.prompt == "user-authored prompt", "legacy custom text should be preserved")
        try expect(result.1.promptSource == .custom, "legacy custom text should remain custom")
        try expect(
            result.2?.contains(#""version":2"#) == true,
            "the migrated payload should be persisted as v2"
        )
    },
    TestCase(name: "saving a built-in prompt still records explicit customization") {
        let suiteName = "AutoRecoverySettingsTests.explicitSave.\(UUID().uuidString)"
        let source = await MainActor.run { () -> AutoRecoveryPromptSource? in
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = AutoRecoverySettingsStore(
                repository: AutoRecoverySettingsRepository(defaults: defaults),
                promptLanguage: .english
            )
            let prompt = store.settings.rule(for: .http400).prompt
            _ = store.savePrompt(for: .http400, prompt: prompt)
            return store.settings.rule(for: .http400).promptSource
        }

        try expect(source == .custom, "an explicit save should always mark the prompt as custom")
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
