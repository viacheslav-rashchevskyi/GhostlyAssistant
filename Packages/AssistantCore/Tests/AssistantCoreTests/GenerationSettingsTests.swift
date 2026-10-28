import Foundation
import Testing
@testable import AssistantCore

private let genCtx = AnswerContext(utterance: "Хто?", recentTranscript: [], history: [], screenshotJPEG: nil, typedByUser: false)

private func request(_ model: ClaudeModel, _ s: GenerationSettings, maxOutput: Int? = nil) throws -> [String: Any] {
    try encodeToDict(RequestBuilder.answer(genCtx, kb: .none, tools: [], model: model, generation: s, maxOutput: maxOutput))
}

@Test func fastSettingsKeepTodaysRequests() {
    #expect(ClaudeModel.haiku.resolve(.fast) == ResolvedGeneration(thinking: .init(type: "disabled"), effort: "low", maxTokens: 2048, adjustments: []))
    #expect(ClaudeModel.sonnet.resolve(.fast) == ResolvedGeneration(thinking: .init(type: "between_tools"), effort: "low", maxTokens: 2048, adjustments: []))
    #expect(ClaudeModel.opus.resolve(.fast) == ResolvedGeneration(thinking: nil, effort: "low", maxTokens: 8192, adjustments: [.alwaysThinks]))
    #expect(ClaudeModel(id: "claude-3-7-sonnet-20250219").resolve(.fast) == ResolvedGeneration(thinking: nil, effort: nil, maxTokens: 2048, adjustments: [.effortUnsupported]))
}

@Test func adaptiveThinkingIsSentWhereSupported() throws {
    let j = try request(.haiku, GenerationSettings(thinking: .adaptive))
    #expect((j["thinking"] as? [String: String]) == ["type": "adaptive"])
    #expect(j["max_tokens"] as? Int == 8192) // auto leaves room for thinking
}

@Test func adaptiveFallsBackOnModelsWithoutIt() {
    let r = ClaudeModel(id: "claude-haiku-4-5").resolve(GenerationSettings(thinking: .adaptive))
    #expect(r.thinking == nil)
    #expect(r.adjustments.contains(.adaptiveUnsupported))
}

@Test func chosenEffortIsSent() throws {
    let j = try request(.opus, GenerationSettings(effort: .high))
    #expect((j["output_config"] as? [String: String]) == ["effort": "high"])
}

@Test func effortAboveHighTurnsThinkingOnWhereOffIsCapped() {
    for model in [ClaudeModel.haiku, .sonnet, ClaudeModel(id: "claude-opus-5")] {
        let r = model.resolve(GenerationSettings(thinking: .off, effort: .max))
        #expect(r.thinking == .init(type: "adaptive"), "\(model.id)")
        #expect(r.effort == "max")
        #expect(r.adjustments.contains(.thinkingTurnedOnForEffort))
    }
    // Sonnet 5 accepts disabled thinking at any effort.
    #expect(ClaudeModel(id: "claude-sonnet-5").resolve(GenerationSettings(effort: .max)).thinking == .init(type: "disabled"))
}

@Test func unsupportedEffortLevelIsLowered() {
    let r = ClaudeModel(id: "claude-opus-4-6").resolve(GenerationSettings(effort: .xhigh))
    #expect(r.effort == "high")
    #expect(r.adjustments.contains(.effortLowered(to: .high)))
}

@Test func explicitMaxTokensIsClampedToTheModel() {
    #expect(ClaudeModel.haiku.resolve(GenerationSettings(maxTokens: 5000), maxOutput: 64_000).maxTokens == 5000)
    let high = ClaudeModel.haiku.resolve(GenerationSettings(maxTokens: 500_000), maxOutput: 64_000)
    #expect(high.maxTokens == 64_000)
    #expect(high.adjustments.contains(.maxTokensClamped(to: 64_000)))
    #expect(ClaudeModel.haiku.resolve(GenerationSettings(maxTokens: 10)).maxTokens == GenerationSettings.minMaxTokens)
}

@Test func modelMaxOutputFallsBackWhenTheAPIDoesNotSayIt() {
    #expect(ClaudeModel.haiku.maxOutputFallback >= 8192)
    #expect(ClaudeModel(id: "claude-3-7-sonnet-20250219").maxOutputFallback == 8192)
}

@Test func toolRoundsKeepTheResolvedSettings() throws {
    let first = RequestBuilder.answer(genCtx, kb: .search, tools: KBTools.definitions, model: .sonnet, generation: GenerationSettings(thinking: .adaptive, effort: .medium))
    let next = RequestBuilder.continuing(first, assistant: [.text("…")], toolResults: [.text("hit")])
    #expect(next.thinking == first.thinking)
    #expect(next.outputConfig == first.outputConfig)
    #expect(next.maxTokens == first.maxTokens)
}

@Test func prewarmMatchesTheAnswerSettings() {
    let s = GenerationSettings(thinking: .adaptive, effort: .high)
    let a = RequestBuilder.answer(genCtx, kb: .none, tools: [], model: .haiku, generation: s)
    let w = RequestBuilder.prewarm(kb: .none, tools: [], model: .haiku, generation: s)
    #expect(w.thinking == a.thinking)
    #expect(w.outputConfig == a.outputConfig)
}

@Test func pipelineAppliesGenerationSetAtRuntime() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так"), .messageStop])])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: ""), screenshots: FakeScreenshots(result: .failure(TestError())),
                              claude: claude, knowledge: NoKnowledge())
    await p.setGeneration(GenerationSettings(effort: .medium, maxTokens: 3000), maxOutput: 64_000)
    await p.ask("Хто?")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(claude.requests.first?.outputConfig?.effort == "medium")
    #expect(claude.requests.first?.maxTokens == 3000)
}

@Test func modelsAPIMaxTokensIsDecoded() throws {
    let body = #"{"type":"model","id":"claude-haiku-5-5","display_name":"Claude Haiku 5.5","created_at":"2026-08-01T00:00:00Z","max_tokens":64000}"#
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    #expect(try d.decode(ClaudeModelInfo.self, from: Data(body.utf8)).maxTokens == 64000)
}
