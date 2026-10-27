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

private func json(_ id: String) throws -> [String: Any] {
    try encodeToDict(RequestBuilder.answer(ctx, kb: .none, tools: [], model: ClaudeModel(id: id)))
}

@Test func fableAlwaysThinksAndFallsBack() throws {
    let j = try json("claude-fable-5-1")
    #expect(j["thinking"] == nil)
    #expect((j["output_config"] as? [String: String]) == ["effort": "low"])
    #expect(j["fallbacks"] as? String == "default")
}

@Test func opus5DisablesThinking() throws {
    let j = try json("claude-opus-5")
    #expect((j["thinking"] as? [String: String]) == ["type": "disabled"])
    #expect(j["fallbacks"] as? String == "default")
}

@Test func opus48RunsWithoutThinkingByOmitting() throws {
    let j = try json("claude-opus-4-8")
    #expect(j["thinking"] == nil)
    #expect((j["output_config"] as? [String: String]) == ["effort": "low"])
    #expect(j["fallbacks"] == nil)
}

@Test func sonnet5DisablesThinking() throws {
    #expect((try json("claude-sonnet-5")["thinking"] as? [String: String]) == ["type": "disabled"])
}

@Test func haiku45SendsNeitherThinkingNorEffort() throws {
    let j = try json("claude-haiku-4-5")
    #expect(j["thinking"] == nil)
    #expect(j["output_config"] == nil)
    #expect(j["fallbacks"] == nil)
}

@Test func unknownOlderModelSendsOnlyTheBasics() throws {
    let j = try json("claude-3-7-sonnet-20250219")
    #expect(j["thinking"] == nil)
    #expect(j["output_config"] == nil)
    #expect(j["fallbacks"] == nil)
}

@Test func knownPrices() {
    #expect(ClaudeModel(id: "claude-haiku-5-5").price == ClaudePrice(input: 0.10, output: 0.50))
    #expect(ClaudeModel(id: "claude-opus-5-5").price == ClaudePrice(input: 4, output: 20))
    #expect(ClaudeModel(id: "claude-fable-5-1").price == ClaudePrice(input: 10, output: 50))
    #expect(ClaudeModel(id: "claude-sonnet-4-6").price == ClaudePrice(input: 3, output: 15))
    #expect(ClaudeModel(id: "claude-3-7-sonnet-20250219").price == nil)
}

@Test func priceLabelUsesCommaDecimals() {
    #expect(ClaudePrice(input: 0.10, output: 0.50).label == "$0,10 / $0,50")
    #expect(ClaudePrice(input: 4, output: 20).label == "$4 / $20")
}

@Test func listModelsParsesAPIResponse() async throws {
    let body = #"{"data":[{"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","created_at":"2026-09-01T00:00:00Z"},{"type":"model","id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5","created_at":"2026-08-01T00:00:00Z"}],"has_more":false}"#
    let t = MockTransport(status: 200, body: body)
    let models = try await ClaudeClient(apiKey: "k", transport: t).listModels()
    #expect(models.map(\.id) == ["claude-opus-5-5", "claude-haiku-5-5"])
    #expect(models.first?.displayName == "Claude Opus 5.5")
    #expect(t.last?.httpMethod == "GET")
    #expect(t.last?.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1000")
}
