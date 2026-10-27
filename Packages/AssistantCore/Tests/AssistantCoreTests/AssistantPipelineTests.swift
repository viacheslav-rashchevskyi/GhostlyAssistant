import Foundation
import Testing
@testable import AssistantCore

struct FakeTranscriber: SpeechTranscribing {
    let text: String
    func transcribe(_ samples: [Float]) async throws -> String { text }
}

struct FakeScreenshots: ScreenshotProviding {
    let result: Result<Data, Error>
    func captureJPEG() async throws -> Data { try result.get() }
}

enum Script {
    case events([SSEEvent])
    case eventsThenError([SSEEvent], Error)
}

final class FakeClaude: MessageStreaming, @unchecked Sendable {
    private var scripts: [Script]
    private let lock = NSLock()
    private(set) var requests: [MessagesRequest] = []

    init(scripts: [Script]) { self.scripts = scripts }

    func streamMessage(_ r: MessagesRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        lock.lock()
        requests.append(r)
        let script = scripts.isEmpty ? .events([.messageStop]) : scripts.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { c in
            switch script {
            case .events(let es):
                es.forEach { c.yield($0) }
                c.finish()
            case .eventsThenError(let es, let e):
                es.forEach { c.yield($0) }
                c.finish(throwing: e)
            }
        }
    }
}

final class FakeKnowledge: KnowledgeProviding, @unchecked Sendable {
    struct Call: Equatable { let tool: String; let input: JSONValue }
    let kbPayload: KBPayload
    let result: [ContentBlock]
    private(set) var calls: [Call] = []

    init(payload: KBPayload, result: [ContentBlock]) {
        kbPayload = payload
        self.result = result
    }

    func payload() async -> KBPayload { kbPayload }
    func tools() async -> [ToolDefinition] { [ToolDefinition(name: "search_kb", description: "d", inputSchema: .object([:]))] }
    func execute(tool: String, input: JSONValue) async -> [ContentBlock] {
        calls.append(Call(tool: tool, input: input))
        return result
    }
}

private let utterance = Utterance(samples: [0.1], endedAt: Date())

private func makePipeline(
    text: String,
    screenshots: ScreenshotProviding = FakeScreenshots(result: .success(Data([7]))),
    claude: FakeClaude,
    knowledge: KnowledgeProviding = NoKnowledge()
) -> AssistantPipeline {
    AssistantPipeline(transcriber: FakeTranscriber(text: text), screenshots: screenshots, claude: claude, knowledge: knowledge)
}

/// Collects events until an answer finishes or fails, or until the timeout passes.
private func collect(_ p: AssistantPipeline, timeout: Duration = .milliseconds(300)) async -> [CardEvent] {
    await withTaskGroup(of: [CardEvent].self) { group in
        group.addTask {
            var out: [CardEvent] = []
            for await e in p.events {
                out.append(e)
                switch e {
                case .answerFinished, .answerFailed: return out
                default: continue
                }
            }
            return out
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}

private extension Array where Element == CardEvent {
    var deltas: [String] {
        compactMap { if case .answerDelta(_, let t) = $0 { t } else { nil } }
    }
    var answerId: UUID? {
        for e in self { if case .answerStarted(let id, _) = e { return id } }
        return nil
    }
}

@Test func answersAQuestion() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "**Бо"), .textDelta(index: 0, text: " так.**"), .messageDelta(stopReason: "end_turn", outputTokens: 4), .messageStop])])
    let p = makePipeline(text: "Чому ви обрали Swift для цього?", claude: claude)
    await p.handle(utterance)
    let ev = await collect(p)
    guard case .answerStarted(_, let q) = ev.first else { Issue.record("no start: \(ev)"); return }
    #expect(q == "Чому ви обрали Swift для цього?")
    #expect(ev.deltas.joined() == "**Бо так.**")
    guard case .answerFinished = ev.last else { Issue.record("not finished: \(ev)"); return }
    #expect(claude.requests[0].messages[0].content.contains(.imageJPEG(Data([7]))))
}

@Test func sentinelProducesNoEvents() async {
    let p = makePipeline(text: "Добрий день усім присутнім", claude: FakeClaude(scripts: [.events([.textDelta(index: 0, text: "∅"), .messageStop])]))
    await p.handle(utterance)
    #expect(await collect(p).isEmpty)
}

@Test func shortUtteranceNeverCallsClaude() async {
    let claude = FakeClaude(scripts: [])
    await makePipeline(text: "так", claude: claude).handle(utterance)
    #expect(claude.requests.isEmpty)
}

@Test func screenshotFailureStillAnswers() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "ok"), .messageStop])])
    let p = makePipeline(text: "Що показано на цьому слайді?", screenshots: FakeScreenshots(result: .failure(TestError())), claude: claude)
    await p.handle(utterance)
    _ = await collect(p)
    #expect(claude.requests.count == 1)
    #expect(!claude.requests[0].messages[0].content.contains { if case .imageJPEG = $0 { true } else { false } })
}

@Test func midStreamFailureKeepsPartialAnswer() async {
    let claude = FakeClaude(scripts: [.eventsThenError([.textDelta(index: 0, text: "Частина")], ClaudeError.stream(type: "overloaded_error", message: "Overloaded"))])
    let p = makePipeline(text: "Поясніть архітектуру вашого рішення", claude: claude)
    await p.handle(utterance)
    let ev = await collect(p)
    #expect(ev.deltas.joined() == "Частина")
    guard let id = ev.answerId else { Issue.record("no start: \(ev)"); return }
    #expect(ev.last == .answerFailed(id: id, message: "Ошибка API (529). Попробую на следующем вопросе."))
}

@Test func failureBeforeAnyTextStillReportsError() async {
    let claude = FakeClaude(scripts: [.eventsThenError([], ClaudeError.network)])
    let p = makePipeline(text: "Поясніть архітектуру вашого рішення", claude: claude)
    await p.handle(utterance)
    let ev = await collect(p)
    guard case .answerFailed(_, let message) = ev.last else { Issue.record("no failure: \(ev)"); return }
    #expect(message == "Нет сети. Попробую на следующем вопросе.")
}

@Test func refusalWithoutTextIsReported() async {
    let claude = FakeClaude(scripts: [.events([.messageDelta(stopReason: "refusal", outputTokens: 0), .messageStop])])
    let p = makePipeline(text: "Поясніть архітектуру вашого рішення", claude: claude)
    await p.handle(utterance)
    guard case .answerFailed(_, let message) = await collect(p).last else { Issue.record(); return }
    #expect(message == "Модель отказалась отвечать.")
}

@Test func toolLoopRunsSearchThenAnswers() async {
    let claude = FakeClaude(scripts: [
        .events([.toolUseStart(index: 0, id: "t1", name: "search_kb"), .inputJSONDelta(index: 0, partialJSON: #"{"query":"кеш"}"#), .blockStop(index: 0), .messageDelta(stopReason: "tool_use", outputTokens: 5), .messageStop]),
        .events([.textDelta(index: 0, text: "Знайшов."), .messageStop])
    ])
    let kb = FakeKnowledge(payload: .search, result: [.text("hit")])
    let p = makePipeline(text: "Що сказано про кешування в документі?", claude: claude, knowledge: kb)
    await p.handle(utterance)
    let ev = await collect(p)
    #expect(ev.contains { if case .kbLookup = $0 { true } else { false } })
    #expect(kb.calls == [.init(tool: "search_kb", input: .object(["query": .string("кеш")]))])
    #expect(claude.requests.count == 2)
    #expect(claude.requests[1].messages.count == 3)
    #expect(claude.requests[1].messages[1].content == [.toolUse(id: "t1", name: "search_kb", input: .object(["query": .string("кеш")]))])
    #expect(claude.requests[1].messages[2].content == [.toolResult(toolUseId: "t1", content: [.text("hit")])])
    #expect(ev.deltas.joined() == "Знайшов.")
}

@Test func finishedAnswerGoesIntoNextRequestHistory() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Перша"), .messageStop]), .events([.textDelta(index: 0, text: "Друга"), .messageStop])])
    let p = makePipeline(text: "Яке перше питання до вас?", claude: claude)
    await p.handle(utterance)
    _ = await collect(p)
    await p.handle(utterance)
    _ = await collect(p)
    #expect(claude.requests[1].messages[0].content.contains(.text("<previous_answers>\nQ: Яке перше питання до вас?\nA: Перша\n</previous_answers>")))
}

@Test func typedQuestionSkipsFilterAndTranscriber() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так"), .messageStop])])
    let p = makePipeline(text: "", claude: claude)
    await p.ask("Хто?")
    _ = await collect(p)
    #expect(claude.requests.count == 1)
    #expect(claude.requests[0].messages[0].content.last == .text("<typed_question>\nХто?\n</typed_question>"))
}
