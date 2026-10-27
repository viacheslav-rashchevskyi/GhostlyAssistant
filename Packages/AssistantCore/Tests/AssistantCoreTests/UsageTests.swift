import Foundation
import Testing
@testable import AssistantCore

@Test func costUsesTieredPrice() {
    // Haiku 5.5: $0.10 input, $0.50 output per MTok.
    let usage = TokenUsage(inputTokens: 200_000, cacheReadTokens: 0, outputTokens: 10_000)
    let cost = usage.cost(price: ClaudePrice(input: 0.10, output: 0.50))
    #expect(abs(cost - (0.2 * 0.10 + 0.01 * 0.50)) < 1e-9)
}

@Test func cacheReadsBilledCheaper() {
    // Cache reads are 0.1x the input rate; they are a subset of input tokens.
    let plain = TokenUsage(inputTokens: 100_000, cacheReadTokens: 0, outputTokens: 0)
    let cached = TokenUsage(inputTokens: 100_000, cacheReadTokens: 90_000, outputTokens: 0)
    let price = ClaudePrice(input: 1, output: 1)
    #expect(cached.cost(price: price) < plain.cost(price: price))
    // 10k fresh input @ $1 + 90k cached @ $0.10 = 0.01 + 0.009 = 0.019
    #expect(abs(cached.cost(price: price) - 0.019) < 1e-9)
}

@Test func usageAccumulates() {
    var total = TokenUsage()
    total.add(TokenUsage(inputTokens: 5, cacheReadTokens: 2, outputTokens: 3))
    total.add(TokenUsage(inputTokens: 10, cacheReadTokens: 4, outputTokens: 6))
    #expect(total == TokenUsage(inputTokens: 15, cacheReadTokens: 6, outputTokens: 9))
}

@Test func costLabelFormatsSmallAmounts() {
    #expect(SessionCost(usd: 0).label == "$0,00")
    #expect(SessionCost(usd: 0.0004).label == "<$0,01")
    #expect(SessionCost(usd: 0.0372).label == "$0,04")
    #expect(SessionCost(usd: 1.5).label == "$1,50")
}

@Test func pipelineReportsUsagePerAnswer() async {
    let claude = FakeClaude(scripts: [.events([
        .messageStart(inputTokens: 1000, cacheReadTokens: 800),
        .textDelta(index: 0, text: "Так"),
        .messageDelta(stopReason: "end_turn", outputTokens: 12),
        .messageStop
    ])])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: ""), screenshots: FakeScreenshots(result: .failure(TestError())),
                              claude: claude, knowledge: NoKnowledge())
    let events = p.events
    await p.ask("Хто?")
    var usage: TokenUsage?
    for await e in events {
        if case .answerFinished(_, _, let u) = e { usage = u; break }
    }
    #expect(usage == TokenUsage(inputTokens: 1000, cacheReadTokens: 800, outputTokens: 12))
}
