import ThreadBeaconCore

let taskOpenPolicyTests = [
    TestCase(name: "task open policy allows an active authorized task") {
        try expect(
            TaskOpenRequestPolicy.evaluate(
                isArchived: false,
                isAuthorized: true,
                isInteractionInProgress: false
            ) == .allowed,
            "an active task should open after explicit Accessibility authorization"
        )
    },
    TestCase(name: "task open policy rejects archived tasks first") {
        try expect(
            TaskOpenRequestPolicy.evaluate(
                isArchived: true,
                isAuthorized: false,
                isInteractionInProgress: true
            ) == .archived,
            "an archived task must never enter the Codex navigation path"
        )
    },
    TestCase(name: "task open policy requires Accessibility authorization") {
        try expect(
            TaskOpenRequestPolicy.evaluate(
                isArchived: false,
                isAuthorized: false,
                isInteractionInProgress: false
            ) == .notAuthorized,
            "an unauthorized request must fail before opening a deep link"
        )
    },
    TestCase(name: "task open policy rejects concurrent Accessibility interaction") {
        try expect(
            TaskOpenRequestPolicy.evaluate(
                isArchived: false,
                isAuthorized: true,
                isInteractionInProgress: true
            ) == .interactionInProgress,
            "task opening must not race another Accessibility operation"
        )
    },
    TestCase(name: "task open result reports only confirmed opening as success") {
        try expect(TaskOpenResult.opened.isOpened, "confirmed opening should be successful")
        try expect(!TaskOpenResult.archived.isOpened, "archived task should not report success")
        try expect(!TaskOpenResult.notAuthorized.isOpened, "missing permission should not report success")
        try expect(
            !TaskOpenResult.interactionInProgress.isOpened,
            "a concurrent operation should not report success"
        )
        try expect(
            !TaskOpenResult.selectionFailed(.selectionFailed).isOpened,
            "target selection failure should not report success"
        )
    },
    TestCase(name: "task open result exposes only actionable failure presentation") {
        try expect(
            !TaskOpenResult.opened.shouldPresentFailure,
            "successful opening should not leave ThreadBeacon showing an alert"
        )
        try expect(
            TaskOpenResult.notAuthorized.shouldOfferAccessibilitySettings,
            "missing permission should offer the macOS Accessibility settings shortcut"
        )
        try expect(
            !TaskOpenResult.selectionFailed(.sourceComposerNotEmpty)
                .shouldOfferAccessibilitySettings,
            "a protected draft should not offer an unrelated permission shortcut"
        )
    }
]
