import Foundation
import Testing
@testable import AssistantCore

private let styleCtx = AnswerContext(utterance: "Хто?", recentTranscript: [], history: [], screenshotJPEG: nil, typedByUser: false)

private func systemTexts(_ r: MessagesRequest) -> [String] {
    r.system.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
}

@Test func balancedStyleAddsNothing() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle())
    #expect(r.system == [.text(SystemPrompt.text, cache: .oneHour)])
}

@Test func briefStyleAddsLengthInstruction() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle(length: .brief))
    let texts = systemTexts(r)
    #expect(texts.count == 2)
    #expect(texts[1].contains("one or two short sentences"))
}

@Test func detailedStyleAddsLengthInstruction() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle(length: .detailed))
    #expect(systemTexts(r)[1].contains("fuller answer"))
}

@Test func customInstructionsAreAppended() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle(custom: "Answer as a student defending the work."))
    #expect(systemTexts(r)[1].contains("Answer as a student defending the work."))
}

@Test func cacheMarkerSitsOnTheLastSystemBlock() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle(length: .brief))
    #expect(r.system.first == .text(SystemPrompt.text))
    guard case .text(_, let cache) = r.system.last else { Issue.record(); return }
    #expect(cache == .oneHour)
}

@Test func blankCustomInstructionsAreIgnored() {
    let r = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: AnswerStyle(custom: "   "))
    #expect(r.system.count == 1)
}

@Test func pipelineAppliesStyleSetAtRuntime() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так"), .messageStop])])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: ""), screenshots: FakeScreenshots(result: .failure(TestError())),
                              claude: claude, knowledge: NoKnowledge())
    await p.setStyle(AnswerStyle(length: .brief))
    await p.ask("Хто?")
    try? await Task.sleep(for: .milliseconds(50))
    #expect(claude.requests.first.map(systemTexts)?.count == 2)
}

@Test func prewarmUsesTheSameSystemPrefixAsAnswers() {
    let style = AnswerStyle(length: .brief)
    let answer = RequestBuilder.answer(styleCtx, kb: .none, tools: [], style: style)
    let warm = RequestBuilder.prewarm(kb: .none, tools: [], style: style)
    #expect(warm.system == answer.system)
}

@Test func thinkingModelsGetRoomForThinkingAndAnswer() {
    #expect(RequestBuilder.answer(styleCtx, kb: .none, tools: [], model: .haiku).maxTokens == 2048)
    #expect(RequestBuilder.answer(styleCtx, kb: .none, tools: [], model: .opus).maxTokens >= 8192)
    #expect(RequestBuilder.answer(styleCtx, kb: .none, tools: [], model: ClaudeModel(id: "claude-fable-5-1")).maxTokens >= 8192)
}
