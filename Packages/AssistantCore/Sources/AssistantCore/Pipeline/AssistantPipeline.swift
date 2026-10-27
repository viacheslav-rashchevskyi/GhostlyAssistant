import Foundation
import os

public protocol SpeechTranscribing: Sendable {
    func transcribe(_ samples: [Float]) async throws -> String
}

public protocol ScreenshotProviding: Sendable {
    func captureJPEG() async throws -> Data
}

public protocol KnowledgeProviding: Sendable {
    func payload() async -> KBPayload
    func tools() async -> [ToolDefinition]
    func execute(tool: String, input: JSONValue) async -> [ContentBlock]
}

public struct NoKnowledge: KnowledgeProviding {
    public init() {}
    public func payload() async -> KBPayload { .none }
    public func tools() async -> [ToolDefinition] { [] }
    public func execute(tool: String, input: JSONValue) async -> [ContentBlock] { [.text("No knowledge base.")] }
}

public enum CardEvent: Equatable, Sendable {
    case answerStarted(id: UUID, question: String)
    case answerDelta(id: UUID, text: String)
    case kbLookup(id: UUID)
    case answerFinished(id: UUID, latency: Latency)
    case answerFailed(id: UUID, message: String)
}

/// Turns finished utterances into streamed answers: transcribe → filter → screenshot → Claude (with optional KB tools).
public actor AssistantPipeline {
    static let maxToolRounds = 3
    private static let log = Logger(subsystem: "local.ghostlyassistant.app", category: "latency")

    public nonisolated let events: AsyncStream<CardEvent>
    private let continuation: AsyncStream<CardEvent>.Continuation
    private let transcriber: SpeechTranscribing
    private let screenshots: ScreenshotProviding
    private let claude: MessageStreaming
    private let knowledge: KnowledgeProviding
    private let now: @Sendable () -> Date
    private var transcript = TranscriptBuffer()

    public init(
        transcriber: SpeechTranscribing,
        screenshots: ScreenshotProviding,
        claude: MessageStreaming,
        knowledge: KnowledgeProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        (events, continuation) = AsyncStream.makeStream(of: CardEvent.self)
        self.transcriber = transcriber
        self.screenshots = screenshots
        self.claude = claude
        self.knowledge = knowledge
        self.now = now
    }

    public func handle(_ u: Utterance) async {
        let t0 = now()
        guard let raw = try? await transcriber.transcribe(u.samples) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let transcribed = now()
        transcript.append(text, at: u.endedAt)
        guard UtteranceFilter.shouldSend(text) else { return }
        let shot = try? await screenshots.captureJPEG()
        Self.log.info("transcribe \(transcribed.timeIntervalSince(t0), format: .fixed(precision: 2))s screenshot \(self.now().timeIntervalSince(transcribed), format: .fixed(precision: 2))s")
        let ctx = AnswerContext(
            utterance: text,
            recentTranscript: Array(transcript.recent(now: u.endedAt).dropLast()),
            history: transcript.history,
            screenshotJPEG: shot,
            typedByUser: false
        )
        await answer(ctx, startedAt: u.endedAt)
    }

    public func ask(_ typed: String) async {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let start = now()
        let ctx = AnswerContext(
            utterance: text,
            recentTranscript: transcript.recent(now: start),
            history: transcript.history,
            screenshotJPEG: try? await screenshots.captureJPEG(),
            typedByUser: true
        )
        await answer(ctx, startedAt: start)
    }

    private struct PendingTool {
        let id: String
        let name: String
        var json = ""
    }

    private func answer(_ ctx: AnswerContext, startedAt: Date) async {
        let id = UUID()
        let kb = await knowledge.payload()
        let tools = await knowledge.tools()
        var request = RequestBuilder.answer(ctx, kb: kb, tools: tools)
        var gate = AnswerGate()
        var started = false
        var fullText = ""
        var firstTextAt: Date?
        var outputTokens = 0
        var stopReason: String?

        func start() {
            guard !started else { return }
            started = true
            continuation.yield(.answerStarted(id: id, question: ctx.utterance))
        }

        do {
            for round in 0...Self.maxToolRounds {
                let requestAt = now()
                var roundText = ""
                var pending: [Int: PendingTool] = [:]
                stopReason = nil
                for try await event in claude.streamMessage(request) {
                    switch event {
                    case .textDelta(_, let t):
                        if roundText.isEmpty {
                            Self.log.info("claude first token \(self.now().timeIntervalSince(requestAt), format: .fixed(precision: 2))s")
                        }
                        roundText += t
                        switch gate.feed(t) {
                        case .suppressed:
                            return
                        case .undecided:
                            break
                        case .emit(let s):
                            if firstTextAt == nil { firstTextAt = now() }
                            start()
                            fullText += s
                            continuation.yield(.answerDelta(id: id, text: s))
                        }
                    case .toolUseStart(let index, let toolId, let name):
                        pending[index] = PendingTool(id: toolId, name: name)
                    case .inputJSONDelta(let index, let part):
                        pending[index]?.json += part
                    case .messageDelta(let reason, let tokens):
                        stopReason = reason
                        outputTokens += tokens
                    default:
                        break
                    }
                }
                guard stopReason == "tool_use", !pending.isEmpty, round < Self.maxToolRounds else { break }
                continuation.yield(.kbLookup(id: id))
                let uses = pending.keys.sorted().compactMap { pending[$0] }
                var assistant: [ContentBlock] = roundText.isEmpty ? [] : [.text(roundText)]
                var results: [ContentBlock] = []
                for use in uses {
                    let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(use.json.utf8))) ?? .object([:])
                    assistant.append(.toolUse(id: use.id, name: use.name, input: input))
                    results.append(.toolResult(toolUseId: use.id, content: await knowledge.execute(tool: use.name, input: input)))
                }
                request = RequestBuilder.continuing(request, assistant: assistant, toolResults: results)
            }
        } catch {
            start()
            continuation.yield(.answerFailed(id: id, message: Self.message(for: error)))
            return
        }

        guard started, let firstTextAt else {
            if stopReason == "refusal" {
                start()
                continuation.yield(.answerFailed(id: id, message: "Модель отказалась отвечать."))
            }
            return
        }
        let finishedAt = now()
        let generation = finishedAt.timeIntervalSince(firstTextAt)
        let latency = Latency(
            timeToFirstToken: firstTextAt.timeIntervalSince(startedAt),
            tokensPerSecond: generation > 0.05 && outputTokens > 0 ? Double(outputTokens) / generation : nil
        )
        Self.log.info("answer first text \(latency.timeToFirstToken, format: .fixed(precision: 2))s \(latency.label, privacy: .public)")
        transcript.addAnswer(QAPair(question: ctx.utterance, answer: fullText))
        continuation.yield(.answerFinished(id: id, latency: latency))
    }

    static func message(for error: Error) -> String {
        switch error as? ClaudeError {
        case .http(let status, _):
            return "Ошибка API (\(status)). Попробую на следующем вопросе."
        case .stream(let type, _):
            return "Ошибка API (\(type == "overloaded_error" ? 529 : 500)). Попробую на следующем вопросе."
        case .network:
            return "Нет сети. Попробую на следующем вопросе."
        case nil:
            return error is URLError
                ? "Нет сети. Попробую на следующем вопросе."
                : "Ошибка API (500). Попробую на следующем вопросе."
        }
    }
}
