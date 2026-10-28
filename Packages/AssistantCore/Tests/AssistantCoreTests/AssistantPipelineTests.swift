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
                case .answerFinished, .answerFailed, .activity(_, .skipped): return out
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
    var question: String? {
        for e in self { if case .answerStarted(_, let q) = e { return q } }
        return nil
    }
    var activities: [Activity] {
        compactMap { if case .activity(_, let a) = $0 { a } else { nil } }
    }
}

@Test func answersAQuestion() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "**Бо"), .textDelta(index: 0, text: " так.**"), .messageDelta(stopReason: "end_turn"), .messageStop])])
    let p = makePipeline(text: "Чому ви обрали Swift для цього?", claude: claude)
    await p.handle(utterance)
    let ev = await collect(p)
    #expect(ev.question == "Чому ви обрали Swift для цього?")
    #expect(ev.deltas.joined() == "**Бо так.**")
    guard case .answerFinished = ev.last else { Issue.record("not finished: \(ev)"); return }
    #expect(claude.requests[0].messages[0].content.contains(.imageJPEG(Data([7]))))
}

@Test func stagesComeBeforeTheAnswerWithOneId() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так."), .messageStop])])
    let p = makePipeline(text: "Чому ви обрали Swift для цього?", claude: claude)
    await p.handle(utterance)
    let ev = await collect(p)
    #expect(ev.activities == [.transcribing, .heard("Чому ви обрали Swift для цього?"), .thinking])
    guard case .activity(let stageId, .transcribing) = ev.first else { Issue.record("no transcribing first: \(ev)"); return }
    #expect(ev.answerId == stageId)
}

@Test func sentinelIsReportedAsSkipped() async {
    let p = makePipeline(text: "Добрий день усім присутнім", claude: FakeClaude(scripts: [.events([.textDelta(index: 0, text: "∅"), .messageStop])]))
    await p.handle(utterance)
    let ev = await collect(p)
    #expect(ev.activities == [.transcribing, .heard("Добрий день усім присутнім"), .thinking, .skipped(.notAQuestion)])
    #expect(ev.answerId == nil)
}

@Test func shortUtteranceIsReportedAsSkipped() async {
    let p = makePipeline(text: "так", claude: FakeClaude(scripts: []))
    await p.handle(utterance)
    #expect(await collect(p).activities == [.transcribing, .heard("так"), .skipped(.tooShort)])
}

@Test func emptyTranscriptIsReportedAsNothingHeard() async {
    let p = makePipeline(text: "  ", claude: FakeClaude(scripts: []))
    await p.handle(utterance)
    #expect(await collect(p).activities == [.transcribing, .skipped(.nothingHeard)])
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
    let claude = FakeClaude(scripts: [.events([.messageDelta(stopReason: "refusal"), .messageStop])])
    let p = makePipeline(text: "Поясніть архітектуру вашого рішення", claude: claude)
    await p.handle(utterance)
    guard case .answerFailed(_, let message) = await collect(p).last else { Issue.record(); return }
    #expect(message == "Модель отказалась отвечать.")
}

@Test func toolLoopRunsSearchThenAnswers() async {
    let claude = FakeClaude(scripts: [
        .events([.toolUseStart(index: 0, id: "t1", name: "search_kb"), .inputJSONDelta(index: 0, partialJSON: #"{"query":"кеш"}"#), .blockStop(index: 0), .messageDelta(stopReason: "tool_use"), .messageStop]),
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
    #expect(await collect(p).activities == [.asked("Хто?"), .thinking])
    #expect(claude.requests.count == 1)
    #expect(claude.requests[0].messages[0].content.last == .text("<typed_question>\nХто?\n</typed_question>"))
}

@Test func skippedUtteranceCanBeAnsweredOnDemand() async {
    let claude = FakeClaude(scripts: [
        .events([.textDelta(index: 0, text: "∅"), .messageStop]),
        .events([.textDelta(index: 0, text: "Відповідь."), .messageStop])
    ])
    let p = makePipeline(text: "Розкажіть про вашу роботу", claude: claude)
    await p.handle(utterance)
    let first = await collect(p)
    guard case .activity(let id, .transcribing) = first.first else { Issue.record("no start: \(first)"); return }
    #expect(first.activities.last == .skipped(.notAQuestion))

    await p.answer(utteranceId: id)
    let second = await collect(p)
    #expect(second.activities == [.thinking])
    #expect(second.answerId == id)
    #expect(second.deltas.joined() == "Відповідь.")
    #expect(claude.requests[1].messages[0].content.last == .text("<typed_question>\nРозкажіть про вашу роботу\n</typed_question>"))
}

@Test func answeringTheLastSkippedUtterance() async {
    let claude = FakeClaude(scripts: [
        .events([.textDelta(index: 0, text: "∅"), .messageStop]),
        .events([.textDelta(index: 0, text: "Так."), .messageStop])
    ])
    let p = makePipeline(text: "Розкажіть про вашу роботу", claude: claude)
    await p.handle(utterance)
    _ = await collect(p)
    #expect(await p.answerLastSkipped() == true)
    #expect(await collect(p).deltas.joined() == "Так.")
}

@Test func nothingSkippedMeansNothingToAnswer() async {
    let p = makePipeline(text: "Розкажіть про вашу роботу", claude: FakeClaude(scripts: []))
    #expect(await p.answerLastSkipped() == false)
}

@Test func tooShortUtteranceCanAlsoBeAnsweredOnDemand() async {
    let claude = FakeClaude(scripts: [.events([.textDelta(index: 0, text: "Так."), .messageStop])])
    let p = makePipeline(text: "А чому?", claude: claude)
    await p.handle(utterance)
    #expect(await collect(p).activities.last == .skipped(.tooShort))
    #expect(await p.answerLastSkipped() == true)
    #expect(await collect(p).deltas.joined() == "Так.")
}
