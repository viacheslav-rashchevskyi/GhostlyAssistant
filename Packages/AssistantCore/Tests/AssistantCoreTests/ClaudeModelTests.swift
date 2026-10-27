import Foundation
import Testing
@testable import AssistantCore

private let ctx = AnswerContext(utterance: "Хто?", recentTranscript: [], history: [], screenshotJPEG: nil, typedByUser: false)

@Test func haikuDisablesThinkingWithoutFallback() throws {
    let j = try encodeToDict(RequestBuilder.answer(ctx, kb: .none, tools: [], model: .haiku))
    #expect(j["model"] as? String == "claude-haiku-5-5")
    #expect((j["thinking"] as? [String: String]) == ["type": "disabled"])
    #expect(j["fallbacks"] == nil)
}

@Test func sonnetUsesBetweenToolsAndDefaultFallback() throws {
    let j = try encodeToDict(RequestBuilder.answer(ctx, kb: .none, tools: [], model: .sonnet))
    #expect(j["model"] as? String == "claude-sonnet-5-5")
    #expect((j["thinking"] as? [String: String]) == ["type": "between_tools"])
    #expect((j["output_config"] as? [String: String]) == ["effort": "low"])
    #expect(j["fallbacks"] as? String == "default")
}

@Test func opusOmitsThinkingAndUsesDefaultFallback() throws {
    let j = try encodeToDict(RequestBuilder.answer(ctx, kb: .none, tools: [], model: .opus))
    #expect(j["model"] as? String == "claude-opus-5-5")
    #expect(j["thinking"] == nil)
    #expect((j["output_config"] as? [String: String]) == ["effort": "low"])
    #expect(j["fallbacks"] as? String == "default")
}

@Test func prewarmAndCountUseTheChosenModel() throws {
    #expect(RequestBuilder.prewarm(kb: .none, tools: [], model: .opus).model == "claude-opus-5-5")
    #expect(RequestBuilder.countTokens(kb: [.text("x")], model: .sonnet).model == "claude-sonnet-5-5")
}

@Test func fallbackRequestCarriesBetaHeader() async throws {
    let t = MockTransport(status: 200, lines: [#"data: {"type":"message_stop"}"#])
    for try await _ in ClaudeClient(apiKey: "k", transport: t).streamMessage(RequestBuilder.answer(ctx, kb: .none, tools: [], model: .opus)) {}
    #expect(t.last?.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
}

@Test func haikuRequestHasNoBetaHeader() async throws {
    let t = MockTransport(status: 200, lines: [#"data: {"type":"message_stop"}"#])
    for try await _ in ClaudeClient(apiKey: "k", transport: t).streamMessage(RequestBuilder.answer(ctx, kb: .none, tools: [], model: .haiku)) {}
    #expect(t.last?.value(forHTTPHeaderField: "anthropic-beta") == nil)
}

@Test func pipelineUsesModelSetAtRuntime() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так"), .messageStop])])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: ""), screenshots: FakeScreenshots(result: .failure(TestError())),
                              claude: claude, knowledge: NoKnowledge())
    await p.setModel(.sonnet)
    await p.ask("Хто?")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(claude.requests.first?.model == "claude-sonnet-5-5")
}

@Test func knowledgePrewarmUsesModelSetAtRuntime() async throws {
    let api = FakeUploader(tokens: 100)
    let store = KnowledgeStore(api: api)
    await store.setModel(.opus)
    _ = await store.configure([try KnowledgeFixtures.makeDir()])
    await store.prewarm()
    #expect(api.sent.first?.model == "claude-opus-5-5")
    #expect(api.counted.first?.model == "claude-opus-5-5")
}
