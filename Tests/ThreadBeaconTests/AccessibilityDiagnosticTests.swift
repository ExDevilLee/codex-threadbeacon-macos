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
    }
]

private struct StubAccessibilityNode {
    let role: String
    let children: [Int]
}
