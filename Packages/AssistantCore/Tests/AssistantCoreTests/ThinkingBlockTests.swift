import Foundation
import Testing
@testable import AssistantCore

@Test func parsesThinkingBlockEvents() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#) == .thinkingStart(index: 0))
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me"}}"#) == .thinkingDelta(index: 0, text: "Let me"))
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQB"}}"#) == .signatureDelta(index: 0, signature: "EqQB"))
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_start","index":1,"content_block":{"type":"redacted_thinking","data":"opaque"}}"#) == .redactedThinking(index: 1, data: "opaque"))
}

@Test func thinkingBlocksEncodeForReplay() throws {
    let t = try encodeToDict(ContentBlock.thinking(text: "", signature: "sig"))
    #expect(t["type"] as? String == "thinking")
    #expect(t["thinking"] as? String == "")
    #expect(t["signature"] as? String == "sig")
    let r = try encodeToDict(ContentBlock.redactedThinking(data: "opaque"))
    #expect(r["type"] as? String == "redacted_thinking")
    #expect(r["data"] as? String == "opaque")
}

@Test func thinkingBlocksRoundTrip() throws {
    for b in [ContentBlock.thinking(text: "x", signature: "s"), .redactedThinking(data: "d")] {
        #expect(try JSONDecoder().decode(ContentBlock.self, from: JSONEncoder().encode(b)) == b)
    }
}

@Test func toolLoopReplaysThinkingBlocksVerbatimAndInOrder() async {
    let claude = FakeClaude(scripts: [
        .events([
            .thinkingStart(index: 0),
            .thinkingDelta(index: 0, text: "Need the docs."),
            .signatureDelta(index: 0, signature: "sig-1"),
            .blockStop(index: 0),
            .toolUseStart(index: 1, id: "t1", name: "search_kb"),
            .inputJSONDelta(index: 1, partialJSON: #"{"query":"кеш"}"#),
            .blockStop(index: 1),
            .messageDelta(stopReason: "tool_use"),
            .messageStop
        ]),
        .events([.textDelta(index: 0, text: "Знайшов."), .messageStop])
    ])
    let kb = FakeKnowledge(payload: .search, result: [.text("hit")])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: "Що сказано про кешування в документі?"),
                              screenshots: FakeScreenshots(result: .failure(TestError())), claude: claude, knowledge: kb)
    await p.handle(Utterance(samples: [0.1], endedAt: Date()))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(claude.requests.count == 2)
    #expect(claude.requests[1].messages[1].content == [
        .thinking(text: "Need the docs.", signature: "sig-1"),
        .toolUse(id: "t1", name: "search_kb", input: .object(["query": .string("кеш")]))
    ])
}

@Test func redactedThinkingIsReplayedToo() async {
    let claude = FakeClaude(scripts: [
        .events([
            .redactedThinking(index: 0, data: "opaque"),
            .blockStop(index: 0),
            .toolUseStart(index: 1, id: "t1", name: "search_kb"),
            .inputJSONDelta(index: 1, partialJSON: #"{"query":"x"}"#),
            .blockStop(index: 1),
            .messageDelta(stopReason: "tool_use"),
            .messageStop
        ]),
        .events([.textDelta(index: 0, text: "Ок."), .messageStop])
    ])
    let p = AssistantPipeline(transcriber: FakeTranscriber(text: "Що сказано про кешування в документі?"),
                              screenshots: FakeScreenshots(result: .failure(TestError())), claude: claude,
                              knowledge: FakeKnowledge(payload: .search, result: [.text("hit")]))
    await p.handle(Utterance(samples: [0.1], endedAt: Date()))
    try? await Task.sleep(for: .milliseconds(100))
    #expect(claude.requests[1].messages[1].content.first == .redactedThinking(data: "opaque"))
}
