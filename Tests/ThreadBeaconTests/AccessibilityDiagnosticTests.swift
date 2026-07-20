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
    TestCase(name: "target identity rejects duplicate renamed titles") {
        let result = AccessibilityTargetIdentityResolver.resolve(
            threadID: "target-id",
            latestTitles: [
                "target-id": "Duplicate title",
                "other-id": "Duplicate title"
            ]
        )
        try expect(
            result == .titleNotUnique(2),
            "duplicate renamed titles must not be used for Accessibility selection"
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
    },
    TestCase(name: "send button policy requires one pressable composer submit button") {
        let candidates = [
            AccessibilityButtonDescriptor(
                role: "AXButton",
                actionNames: ["AXPress"],
                domClassNames: ["size-token-button-composer", "bg-token-foreground"]
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
            domClassNames: ["size-token-button-composer", "bg-token-foreground"]
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
    }
]

private struct StubAccessibilityNode {
    let role: String
    let children: [Int]
}
