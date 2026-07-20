import Foundation

public struct AccessibilityStructureCounts: Equatable, Sendable {
    public let windowCount: Int
    public let textAreaCount: Int
    public let visitedNodeCount: Int

    public init(windowCount: Int, textAreaCount: Int, visitedNodeCount: Int) {
        self.windowCount = windowCount
        self.textAreaCount = textAreaCount
        self.visitedNodeCount = visitedNodeCount
    }
}

public enum AccessibilityStructureScanner {
    public static func scan<Node>(
        roots: [Node],
        maximumNodeCount: Int = 10_000,
        role: (Node) -> String?,
        children: (Node) -> [Node]
    ) -> AccessibilityStructureCounts {
        var stack = roots
        var windowCount = 0
        var textAreaCount = 0
        var visitedNodeCount = 0

        while let node = stack.popLast(), visitedNodeCount < maximumNodeCount {
            visitedNodeCount += 1
            switch role(node) {
            case "AXWindow": windowCount += 1
            case "AXTextArea": textAreaCount += 1
            default: break
            }
            stack.append(contentsOf: children(node))
        }

        return AccessibilityStructureCounts(
            windowCount: windowCount,
            textAreaCount: textAreaCount,
            visitedNodeCount: visitedNodeCount
        )
    }
}
