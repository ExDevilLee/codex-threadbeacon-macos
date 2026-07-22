import Foundation
import ThreadBeaconCore

let accessibilityDiagnosticTests = [
    TestCase(name: "accessibility diagnostic exposes only structural counts") {
        let result = AccessibilityDiagnosticResult.ready(
            windowCount: 2,
            textAreaCount: 1,
            visitedNodeCount: 240
        )

        try expect(result.isReady, "a successful AX scan should be ready")
        try expect(result.windowCount == 2, "result should retain the window count")
        try expect(result.textAreaCount == 1, "result should retain the text area count")
        try expect(result.visitedNodeCount == 240, "result should retain the visited node count")
    },
    TestCase(name: "accessibility diagnostic keeps authorization failure closed") {
        let result = AccessibilityDiagnosticResult.notAuthorized

        try expect(!result.isReady, "an unauthorized AX scan must not be ready")
        try expect(result.windowCount == nil, "authorization failure must not expose scan counts")
        try expect(result.textAreaCount == nil, "authorization failure must not expose scan counts")
        try expect(result.visitedNodeCount == nil, "authorization failure must not expose scan counts")
    },
    TestCase(name: "accessibility structure scan counts roles within its node limit") {
        let nodes = [
            StubAccessibilityNode(role: "AXApplication", children: [1, 2]),
            StubAccessibilityNode(role: "AXWindow", children: [3]),
            StubAccessibilityNode(role: "AXWindow", children: []),
            StubAccessibilityNode(role: "AXTextArea", children: [4]),
            StubAccessibilityNode(role: "AXTextArea", children: [])
        ]

        let counts = AccessibilityStructureScanner.scan(
            roots: [0],
            maximumNodeCount: 4,
            role: { nodes[$0].role },
            children: { nodes[$0].children }
        )

        try expect(counts.windowCount == 2, "scan should count windows before reaching the limit")
        try expect(counts.textAreaCount == 1, "scan should stop before visiting nodes past the limit")
        try expect(counts.visitedNodeCount == 4, "scan should enforce the node limit")
    },
    TestCase(name: "composer safety policy accepts only empty or verified placeholder values") {
        try expect(
            AccessibilityComposerSafetyPolicy.canTemporarilyReplace(value: ""),
            "an empty composer should be safe for temporary validation"
        )
        try expect(
            AccessibilityComposerSafetyPolicy.canTemporarilyReplace(value: "  随心输入\n"),
            "the verified Codex placeholder should be treated as empty"
        )
        try expect(
            !AccessibilityComposerSafetyPolicy.canTemporarilyReplace(value: "尚未发送的草稿"),
            "a real draft must never be overwritten"
        )
        try expect(
            AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
                value: "AX stale value",
                hasVerifiedPlaceholderDescendant: true
            ),
            "a verified placeholder subtree should override a stale accessibility value"
        )
        try expect(
            !AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
                value: "尚未发送的草稿",
                hasVerifiedPlaceholderDescendant: false
            ),
            "a nonempty value without placeholder evidence must remain protected"
        )
        try expect(
            !AccessibilityComposerSafetyPolicy.canTemporarilyReplace(
                value: nil,
                hasVerifiedPlaceholderDescendant: true
            ),
            "an unreadable value must remain protected even when placeholder evidence exists"
        )
    },
    TestCase(name: "composer validation succeeds only after verified cleanup") {
        try expect(
            AccessibilityComposerValidationResult.verified.isVerified,
            "write, readback, and cleanup verification should be successful"
        )
        try expect(
            !AccessibilityComposerValidationResult.composerNotEmpty.isVerified,
            "a protected composer must fail closed"
        )
        try expect(
            !AccessibilityComposerValidationResult.cleanupFailed.isVerified,
            "failed cleanup must never be reported as successful"
        )
    },
    TestCase(name: "target identity resolves only a unique renamed title") {
        let titles = [
            "target-id": "Target task",
            "other-id": "Other task"
        ]
        try expect(
            AccessibilityTargetIdentityResolver.resolve(
                threadID: " target-id ",
                latestTitles: titles
            ) == .resolved(
                AccessibilityTargetIdentity(threadID: "target-id", title: "Target task")
            ),
            "a trimmed task ID with a unique renamed title should resolve"
        )
        try expect(
            AccessibilityTargetIdentityResolver.resolve(
                threadID: "missing-id",
                latestTitles: titles
            ) == .titleUnavailable,
            "an unknown task ID must fail closed"
        )
    },
    TestCase(name: "target identity keeps the requested ID when renamed titles are duplicated") {
        let result = AccessibilityTargetIdentityResolver.resolve(
            threadID: "target-id",
            latestTitles: [
                "target-id": "Duplicate title",
                "other-id": "Duplicate title"
            ]
        )
        try expect(
            result == .resolved(
                AccessibilityTargetIdentity(threadID: "target-id", title: "Duplicate title")
            ),
            "the deep link should target the requested ID while the title confirms the destination"
        )
    },
    TestCase(name: "target deep link preserves the normalized task ID") {
        try expect(
            AccessibilityThreadDeepLink.url(threadID: " target-id ")?.absoluteString
                == "codex://threads/target-id",
            "the deep link must route with the exact normalized task ID"
        )
    },
    TestCase(name: "target interaction preflight stops while Codex is frontmost") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .unattended,
                isCodexFrontmost: true,
                isCurrentTargetConfirmed: false,
                sourceComposerValues: ["unfinished draft"]
            ) == .codexFrontmost,
            "unattended navigation must not interrupt active Codex interaction when a draft exists"
        )
    },
    TestCase(name: "target interaction preflight allows safe foreground navigation with an empty composer") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .unattended,
                isCodexFrontmost: true,
                isCurrentTargetConfirmed: false,
                sourceComposerValues: [""]
            ) == .safe,
            "automatic recovery may deep-link to the failed task when the only foreground composer is empty"
        )
    },
    TestCase(name: "target interaction preflight allows confirmed frontmost recovery") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .unattended,
                isCodexFrontmost: true,
                isCurrentTargetConfirmed: true,
                sourceComposerValues: [""]
            ) == .safe,
            "automatic recovery should proceed without navigation when the failed task is confirmed"
        )
    },
    TestCase(name: "target interaction preflight preserves a confirmed task draft") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .unattended,
                isCodexFrontmost: true,
                isCurrentTargetConfirmed: true,
                sourceComposerValues: ["unfinished draft"]
            ) == .sourceComposerNotEmpty,
            "automatic recovery must not replace a draft even on the confirmed target"
        )
    },
    TestCase(name: "target interaction preflight allows explicit action while Codex is frontmost") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .userInitiated,
                isCodexFrontmost: true,
                sourceComposerValues: [""]
            ) == .safe,
            "an explicit action can proceed after the user has reviewed the target"
        )
    },
    TestCase(name: "target interaction preflight stops when the current task has a draft") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .userInitiated,
                isCodexFrontmost: false,
                sourceComposerValues: ["unfinished draft"]
            ) == .sourceComposerNotEmpty,
            "target navigation must not move an existing draft to another task"
        )
    },
    TestCase(name: "target interaction preflight allows an empty background composer") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .userInitiated,
                isCodexFrontmost: false,
                sourceComposerValues: [" \n"]
            ) == .safe,
            "an inactive Codex task with no draft should allow explicit navigation"
        )
    },
    TestCase(name: "target interaction preflight rejects ambiguous source composers") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .userInitiated,
                isCodexFrontmost: false,
                sourceComposerValues: ["", ""]
            ) == .sourceComposerNotUnique(2),
            "multiple source composers must fail closed"
        )
    },
    TestCase(name: "target interaction preflight rejects an unreadable source composer") {
        try expect(
            AccessibilityInteractionPreflight.evaluate(
                mode: .userInitiated,
                isCodexFrontmost: false,
                sourceComposerValues: [nil]
            ) == .sourceComposerValueUnavailable,
            "an unreadable composer value must never be treated as empty"
        )
    },
    TestCase(name: "target selection reports success only after identity confirmation") {
        try expect(
            AccessibilityTargetSelectionResult.selected.isSelected,
            "a confirmed selection should be successful"
        )
        try expect(
            !AccessibilityTargetSelectionResult.targetHeaderNotUnique(0).isSelected,
            "a missing target header must fail closed"
        )
        try expect(
            !AccessibilityTargetSelectionResult.codexInteractionInProgress.isSelected,
            "active Codex interaction must fail closed"
        )
        try expect(
            !AccessibilityTargetSelectionResult.sourceComposerNotEmpty.isSelected,
            "a source draft must fail closed"
        )
        try expect(
            !AccessibilityTargetSelectionResult.sourceComposerNotUnique(2).isSelected,
            "ambiguous source composers must fail closed"
        )
    },
    TestCase(name: "target selection exposes actionable diagnostic codes") {
        try expect(
            AccessibilityTargetSelectionResult.codexInteractionInProgress.diagnosticCode
                == "codex_frontmost",
            "frontmost safety stops must remain distinguishable in recovery logs"
        )
        try expect(
            AccessibilityTargetSelectionResult.targetHeaderNotUnique(0).diagnosticCode
                == "target_header_count_0",
            "missing target headers must report their observed count"
        )
        try expect(
            AccessibilityTargetSelectionResult.composerNotUnique(2).diagnosticCode
                == "composer_count_2",
            "ambiguous target composers must report their observed count"
        )
    },
    TestCase(name: "send button policy requires one pressable composer submit button") {
        let candidates = [
            AccessibilityButtonDescriptor(
                role: "AXButton",
                actionNames: ["AXPress"],
                domClassNames: ["size-token-button-composer", "bg-token-foreground"],
                description: "发送"
            ),
            AccessibilityButtonDescriptor(
                role: "AXButton",
                actionNames: ["AXPress"],
                domClassNames: ["size-token-button-composer", "border-token-border"]
            )
        ]
        try expect(
            AccessibilitySendButtonPolicy.uniqueCandidateIndex(in: candidates) == 0,
            "only the pressable composer submit button should be selected"
        )
    },
    TestCase(name: "send button policy fails closed for duplicate candidates") {
        let candidate = AccessibilityButtonDescriptor(
            role: "AXButton",
            actionNames: ["AXPress"],
            domClassNames: ["size-token-button-composer", "bg-token-foreground"],
            description: "Send"
        )
        try expect(
            AccessibilitySendButtonPolicy.uniqueCandidateIndex(in: [candidate, candidate]) == nil,
            "multiple submit candidates must never be guessed"
        )
        let disabled = AccessibilityButtonDescriptor(
            role: "AXButton",
            actionNames: ["AXPress"],
            domClassNames: ["size-token-button-composer", "bg-token-foreground"],
            isEnabled: false
        )
        try expect(
            AccessibilitySendButtonPolicy.uniqueCandidateIndex(in: [disabled]) == nil,
            "a disabled submit button must never be pressed"
        )
    },
    TestCase(name: "send button policy rejects stop and unrelated composer actions") {
        let stop = AccessibilityButtonDescriptor(
            role: "AXButton",
            actionNames: ["AXPress"],
            domClassNames: ["size-token-button-composer", "bg-token-foreground"],
            description: "停止"
        )
        let unrelated = AccessibilityButtonDescriptor(
            role: "AXButton",
            actionNames: ["AXPress"],
            domClassNames: ["size-token-button-composer", "bg-token-foreground"],
            description: "Voice input"
        )
        try expect(
            AccessibilitySendButtonPolicy.candidateIndices(in: [stop, unrelated]).isEmpty,
            "shared composer styling must not make stop or voice actions send candidates"
        )
    },
    TestCase(name: "send button policy accepts the current unlabeled Codex submit button") {
        let currentSubmit = AccessibilityButtonDescriptor(
            role: "AXButton",
            actionNames: ["AXPress"],
            domClassNames: ["size-token-button-composer", "bg-token-foreground"]
        )
        try expect(
            AccessibilitySendButtonPolicy.uniqueCandidateIndex(in: [currentSubmit]) == 0,
            "the structurally unique submit button may omit every accessible text attribute"
        )
    },
    TestCase(name: "recovery send succeeds only after rollout confirmation") {
        try expect(
            AccessibilityRecoverySendResult.verified.isVerified,
            "rollout-confirmed delivery should be successful"
        )
        try expect(
            !AccessibilityRecoverySendResult.sentUnconfirmed.isVerified,
            "an unconfirmed press must never be reported as successful"
        )
        try expect(
            AccessibilityRecoverySendResult.sentUnconfirmed.didTriggerSend,
            "an unconfirmed press must prevent automatic retries"
        )
    },
    TestCase(name: "recovery send requires the currently verified task ID") {
        try expect(
            AccessibilityVerifiedTargetPolicy.canSend(
                threadID: " target-id ",
                selectedThreadID: "target-id"
            ),
            "the normalized input must match the verified task ID"
        )
        try expect(
            !AccessibilityVerifiedTargetPolicy.canSend(
                threadID: "other-id",
                selectedThreadID: "target-id"
            ),
            "changing the target ID must invalidate send eligibility"
        )
    },
    TestCase(name: "foreground restoration allows only the same Codex process") {
        let original = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 101
        )
        let codex = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 202
        )

        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: original,
                currentFrontmostApplication: codex,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .restore,
            "unattended recovery may restore when the same Codex process remains frontmost"
        )

        let replacementCodex = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 303
        )
        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: original,
                currentFrontmostApplication: replacementCodex,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipFrontmostApplicationChanged,
            "a different process must not be treated as the Codex instance activated by recovery"
        )

        let reusedProcessIdentifier = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: codex.processIdentifier
        )
        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: original,
                currentFrontmostApplication: reusedProcessIdentifier,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipFrontmostApplicationChanged,
            "a reused process ID with another bundle must not pass the Codex identity check"
        )
    },
    TestCase(name: "foreground restoration respects explicit user focus changes") {
        let original = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 101
        )
        let codex = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 202
        )
        let browser = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 303
        )

        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: original,
                currentFrontmostApplication: browser,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipFrontmostApplicationChanged,
            "a third foreground app means the user has taken control of focus"
        )
        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .userInitiated,
                originalApplication: original,
                currentFrontmostApplication: codex,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipUserInitiated,
            "explicit navigation and debug sends must leave Codex frontmost"
        )
    },
    TestCase(name: "foreground restoration fails closed for invalid original apps") {
        let codex = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 202
        )

        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: nil,
                currentFrontmostApplication: codex,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipOriginalApplicationUnavailable,
            "missing original app identity must skip restoration"
        )
        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: codex,
                currentFrontmostApplication: codex,
                codexApplication: codex,
                isOriginalApplicationTerminated: false
            ) == .skipOriginalApplicationIsCodex,
            "Codex must never be restored as the app displaced by unattended recovery"
        )
        let original = AccessibilityApplicationIdentity(
            bundleIdentifier: "com.apple.dt.Xcode",
            processIdentifier: 101
        )
        try expect(
            AccessibilityForegroundRestorationPolicy.evaluate(
                mode: .unattended,
                originalApplication: original,
                currentFrontmostApplication: codex,
                codexApplication: codex,
                isOriginalApplicationTerminated: true
            ) == .skipOriginalApplicationTerminated,
            "a terminated original app must not be relaunched or guessed"
        )
    }
]

private struct StubAccessibilityNode {
    let role: String
    let children: [Int]
}
