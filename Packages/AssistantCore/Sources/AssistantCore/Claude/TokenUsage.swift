import Foundation

/// Token counts for one or more requests. `cacheReadTokens` is the part of `inputTokens` that was a cache hit.
public struct TokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, cacheReadTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    public mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cacheReadTokens += other.cacheReadTokens
        outputTokens += other.outputTokens
    }

    /// Dollar cost at the given per-MTok price; cache reads are billed at 0.1x the input rate.
    public func cost(price: ClaudePrice) -> Double {
        let freshInput = max(0, inputTokens - cacheReadTokens)
        let million = 1_000_000.0
        return Double(freshInput) / million * price.input
            + Double(cacheReadTokens) / million * price.input * 0.1
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
