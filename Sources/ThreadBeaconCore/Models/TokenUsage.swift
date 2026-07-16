import Foundation

public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        reasoningOutputTokens: Int64,
        totalTokens: Int64
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public var uncachedInputTokens: Int64 {
        inputTokens - cachedInputTokens
    }

    public var cacheRatio: Double? {
        inputTokens > 0 ? Double(cachedInputTokens) / Double(inputTokens) : nil
    }

    public func subtracting(_ baseline: TokenUsage) -> TokenUsage? {
        let input = inputTokens - baseline.inputTokens
        let cachedInput = cachedInputTokens - baseline.cachedInputTokens
        let output = outputTokens - baseline.outputTokens
        let reasoningOutput = reasoningOutputTokens - baseline.reasoningOutputTokens
        let total = totalTokens - baseline.totalTokens
        guard input >= 0,
              cachedInput >= 0,
              output >= 0,
              reasoningOutput >= 0,
              total >= 0 else {
            return nil
        }
        return TokenUsage(
            inputTokens: input,
            cachedInputTokens: cachedInput,
            outputTokens: output,
            reasoningOutputTokens: reasoningOutput,
            totalTokens: total
        )
    }
}

public struct TokenUsageSnapshot: Equatable, Sendable {
    public let totalTokens: Int64
    public let cumulative: TokenUsage?
    public let currentTurn: TokenUsage?
    public let updatedAt: Date?

    public init(
        totalTokens: Int64,
        cumulative: TokenUsage?,
        currentTurn: TokenUsage?,
        updatedAt: Date?
    ) {
        self.totalTokens = totalTokens
        self.cumulative = cumulative
        self.currentTurn = currentTurn
        self.updatedAt = updatedAt
    }
}
