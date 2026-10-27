import Foundation

/// Token counts for one or more requests, as the API reports them: `inputTokens` is only the uncached
/// remainder; cache reads and cache writes are separate, so the whole prompt is the sum of the three.
public struct TokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, cacheReadTokens: Int = 0, cacheCreationTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.outputTokens = outputTokens
    }

    public var promptTokens: Int { inputTokens + cacheReadTokens + cacheCreationTokens }

    public mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreationTokens += other.cacheCreationTokens
        outputTokens += other.outputTokens
    }

    /// Dollar cost. Cache reads and 1-hour cache writes use the model's own prices when known,
    /// otherwise the standard 0.1x and 2x of the base input price.
    public func cost(price: ClaudePrice) -> Double {
        let million = 1_000_000.0
        return Double(inputTokens) / million * price.input
            + Double(cacheReadTokens) / million * (price.cacheRead ?? price.input * 0.1)
            + Double(cacheCreationTokens) / million * (price.cacheWrite ?? price.input * 2)
            + Double(outputTokens) / million * price.output
    }
}

/// A running session cost, formatted for the chat header.
public struct SessionCost: Equatable, Sendable {
    public let usd: Double

    public init(usd: Double) {
        self.usd = usd
    }

    /// "$0,04", or "<$0,01" for a non-zero amount that rounds to zero.
    public var label: String {
        if usd > 0 && usd < 0.005 { return "<$0,01" }
        return "$" + String(format: "%.2f", usd).replacingOccurrences(of: ".", with: ",")
    }
}
