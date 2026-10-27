import Foundation
import Testing
@testable import AssistantCore

private let ctx = AnswerContext(
    utterance: "Чому такий алгоритм?",
    recentTranscript: ["Доброго дня."],
    history: [QAPair(question: "Мова?", answer: "Swift")],
    screenshotJPEG: Data([9]),
    typedByUser: false
)

private func isImage(_ b: ContentBlock) -> Bool {
    if case .imageJPEG = b { true } else { false }
}

@Test func pinsModelAndLatencySettings() throws {
    let j = try encodeToDict(RequestBuilder.answer(ctx, kb: .none, tools: []))
    #expect(j["model"] as? String == "claude-haiku-5-5")
    #expect(j["max_tokens"] as? Int == 2048)
    #expect(j["stream"] as? Bool == true)
    #expect((j["thinking"] as? [String: String]) == ["type": "disabled"])
    #expect((j["output_config"] as? [String: String]) == ["effort": "low"])
    #expect(j["temperature"] == nil)
    #expect(j["tools"] == nil)
}

@Test func inlineKBComesFirstAndOnlyLastKBBlockIsCached() {
    let kb: [ContentBlock] = [.document(fileId: "f1", title: "a.pdf"), .text("notes")]
    let r = RequestBuilder.answer(ctx, kb: .inline(kb), tools: [])
    let c = r.messages[0].content
    #expect(c[0] == .document(fileId: "f1", title: "a.pdf"))
    #expect(c[1] == .text("notes", cache: .oneHour))
    #expect(c.contains(.imageJPEG(Data([9]))))
    #expect(c.last == .text("<current_utterance>\nЧому такий алгоритм?\n</current_utterance>"))
}

@Test func withoutKBTheSystemPromptIsCached() {
    #expect(RequestBuilder.answer(ctx, kb: .none, tools: []).system == [.text(SystemPrompt.text, cache: .oneHour)])
}

@Test func noScreenshotMeansNoImage() {
    var c2 = ctx
    c2.screenshotJPEG = nil
    #expect(!RequestBuilder.answer(c2, kb: .none, tools: []).messages[0].content.contains(where: isImage))
}

@Test func typedQuestionUsesTypedTag() {
    var c2 = ctx
    c2.typedByUser = true
    #expect(RequestBuilder.answer(c2, kb: .none, tools: []).messages[0].content.last == .text("<typed_question>\nЧому такий алгоритм?\n</typed_question>"))
}

@Test func transcriptAndHistoryAreTagged() {
    let texts = RequestBuilder.answer(ctx, kb: .none, tools: []).messages[0].content.compactMap { b -> String? in
        if case .text(let t, _) = b { t } else { nil }
    }
    #expect(texts.contains("<recent_transcript>\nДоброго дня.\n</recent_transcript>"))
    #expect(texts.contains("<previous_answers>\nQ: Мова?\nA: Swift\n</previous_answers>"))
}

@Test func emptyTranscriptAndHistoryAreOmitted() {
    let c2 = AnswerContext(utterance: "Хто?", recentTranscript: [], history: [], screenshotJPEG: nil, typedByUser: false)
    #expect(RequestBuilder.answer(c2, kb: .none, tools: []).messages[0].content == [.text("<current_utterance>\nХто?\n</current_utterance>")])
}

@Test func searchModeIncludesTools() throws {
    let tool = ToolDefinition(name: "search_kb", description: "d", inputSchema: .object(["type": .string("object")]))
    let j = try encodeToDict(RequestBuilder.answer(ctx, kb: .search, tools: [tool]))
    let tools = j["tools"] as! [[String: Any]]
    #expect(tools[0]["name"] as? String == "search_kb")
    #expect(tools[0]["input_schema"] != nil)
}

@Test func continuingAppendsAssistantAndToolResults() {
    let r = RequestBuilder.answer(ctx, kb: .search, tools: [])
    let next = RequestBuilder.continuing(r, assistant: [.toolUse(id: "t", name: "search_kb", input: .object([:]))], toolResults: [.toolResult(toolUseId: "t", content: [.text("hit")])])
    #expect(next.messages.count == 3)
    #expect(next.messages[1].role == .assistant)
    #expect(next.messages[2].role == .user)
}

@Test func prewarmHasZeroMaxTokensAndNoStream() throws {
    let j = try encodeToDict(RequestBuilder.prewarm(kb: .inline([.text("x")]), tools: []))
    #expect(j["max_tokens"] as? Int == 0)
    #expect(j["stream"] as? Bool == false)
}

@Test func countTokensRequestHasKBOnly() throws {
    let j = try encodeToDict(RequestBuilder.countTokens(kb: [.text("x")]))
    #expect(j["model"] as? String == "claude-haiku-5-5")
    #expect(j["max_tokens"] == nil)
    #expect(j["stream"] == nil)
    #expect(((j["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?.first?["text"] as? String == "x")
}
