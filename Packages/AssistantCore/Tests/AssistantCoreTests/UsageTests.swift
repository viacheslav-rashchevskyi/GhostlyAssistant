import Foundation
import Testing
@testable import AssistantCore

private let opusLike = ClaudePrice(input: 4, output: 20, cacheRead: 0.20, cacheWrite: 8)

@Test func inputTokensAreTheUncachedRemainderOnly() {
    // API semantics: total prompt = input + cacheRead + cacheCreation; each is billed at its own rate.
    let usage = TokenUsage(inputTokens: 1_000, cacheReadTokens: 9_000, cacheCreationTokens: 0, outputTokens: 100)
    let expected = 1_000 * 4e-6 + 9_000 * 0.20e-6 + 100 * 20e-6
    #expect(abs(usage.cost(price: opusLike) - expected) < 1e-12)
}

@Test func cacheWritesUseTheWritePrice() {
    let usage = TokenUsage(inputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 50_000, outputTokens: 0)
    #expect(abs(usage.cost(price: opusLike) - 50_000 * 8e-6) < 1e-12)
}

@Test func missingCachePricesFallBackToStandardMultipliers() {
    // 0.1x for reads, 2x for 1-hour writes.
    let price = ClaudePrice(input: 1, output: 5)
    let usage = TokenUsage(inputTokens: 0, cacheReadTokens: 1_000_000, cacheCreationTokens: 1_000_000, outputTokens: 0)
    #expect(abs(usage.cost(price: price) - (0.1 + 2.0)) < 1e-9)
}

@Test func usageAccumulates() {
    var total = TokenUsage()
    total.add(TokenUsage(inputTokens: 5, cacheReadTokens: 2, cacheCreationTokens: 1, outputTokens: 3))
    total.add(TokenUsage(inputTokens: 10, cacheReadTokens: 4, cacheCreationTokens: 2, outputTokens: 6))
    #expect(total == TokenUsage(inputTokens: 15, cacheReadTokens: 6, cacheCreationTokens: 3, outputTokens: 9))
    #expect(total.promptTokens == 15 + 6 + 3)
}

@Test func costLabelFormatsSmallAmounts() {
    #expect(SessionCost(usd: 0).label == "$0,00")
    #expect(SessionCost(usd: 0.0004).label == "<$0,01")
    #expect(SessionCost(usd: 0.0372).label == "$0,04")
    #expect(SessionCost(usd: 1.5).label == "$1,50")
}

@Test func messageStartParsesCacheCreation() throws {
    let e = try SSEParser.parse(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":12,"cache_read_input_tokens":3000,"cache_creation_input_tokens":40}}}"#)
    #expect(e == .messageStart(inputTokens: 12, cacheReadTokens: 3000, cacheCreationTokens: 40))
}

private func pipeline(_ claude: FakeClaude, text: String = "") -> AssistantPipeline {
    AssistantPipeline(transcriber: FakeTranscriber(text: text), screenshots: FakeScreenshots(result: .failure(TestError())),
                      claude: claude, knowledge: NoKnowledge())
}

private func firstUsage(_ p: AssistantPipeline) async -> TokenUsage? {
    for await e in p.events { if case .usage(_, let u) = e { return u } }
    return nil
}

@Test func usageIsReportedForAnsweredQuestions() async {
    let claude = FakeClaude(scripts: [.events([
        .messageStart(inputTokens: 1000, cacheReadTokens: 800, cacheCreationTokens: 0),
        .textDelta(index: 0, text: "Так"),
        .messageDelta(stopReason: "end_turn", outputTokens: 12),
        .messageStop
    ])])
    let p = pipeline(claude)
    await p.ask("Хто?")
    #expect(await firstUsage(p) == TokenUsage(inputTokens: 1000, cacheReadTokens: 800, cacheCreationTokens: 0, outputTokens: 12))
}

@Test func usageIsReportedEvenWhenTheAnswerIsSuppressed() async {
    // Most utterances in a call end as ∅ but still cost a full prompt.
    let claude = FakeClaude(scripts: [.events([
        .messageStart(inputTokens: 500, cacheReadTokens: 3000, cacheCreationTokens: 0),
        .textDelta(index: 0, text: "∅"),
        .messageDelta(stopReason: "end_turn", outputTokens: 2),
        .messageStop
    ])])
    let p = pipeline(claude, text: "Добрий день усім присутнім")
    await p.handle(Utterance(samples: [0.1], endedAt: Date()))
    #expect(await firstUsage(p) == TokenUsage(inputTokens: 500, cacheReadTokens: 3000, cacheCreationTokens: 0, outputTokens: 2))
}
