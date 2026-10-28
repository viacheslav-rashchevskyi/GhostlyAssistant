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

/// What the pipeline is doing with one utterance before (or instead of) answering.
public enum Activity: Equatable, Sendable {
    /// A question the user typed or dictated (not heard from the call).
    case asked(String)
    case transcribing
    case heard(String)
    case thinking
    case skipped(SkipReason)
}

public enum SkipReason: Equatable, Sendable {
    case nothingHeard
    case tooShort
    case notAQuestion
}

/// Stage and answer events share the utterance's id.
public enum CardEvent: Equatable, Sendable {
    case activity(id: UUID, Activity)
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
    private var model = ClaudeModel.haiku
    private var style = AnswerStyle()
    private var generation = GenerationSettings.fast
    /// The answering model's output cap from the Models API, if known.
    private var maxOutput: Int?
    /// Heard utterances that weren't answered, so the user can ask for an answer anyway (newest last).
    private var skipped: [(id: UUID, text: String)] = []

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

    public func setModel(_ model: ClaudeModel) {
        self.model = model
    }

    public func setStyle(_ style: AnswerStyle) {
        self.style = style
    }

    public func setGeneration(_ generation: GenerationSettings, maxOutput: Int?) {
        self.generation = generation
        self.maxOutput = maxOutput
    }

    public func handle(_ u: Utterance) async {
        let id = UUID()
        let t0 = now()
        continuation.yield(.activity(id: id, .transcribing))
        let text = ((try? await transcriber.transcribe(u.samples)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            continuation.yield(.activity(id: id, .skipped(.nothingHeard)))
            return
        }
        let transcribed = now()
        continuation.yield(.activity(id: id, .heard(text)))
        transcript.append(text, at: u.endedAt)
        guard UtteranceFilter.shouldSend(text) else {
            remember(id, text)
            continuation.yield(.activity(id: id, .skipped(.tooShort)))
            return
        }
        continuation.yield(.activity(id: id, .thinking))
        let shot = try? await screenshots.captureJPEG()
        Self.log.info("transcribe \(transcribed.timeIntervalSince(t0), format: .fixed(precision: 2))s screenshot \(self.now().timeIntervalSince(transcribed), format: .fixed(precision: 2))s")
        let ctx = AnswerContext(
            utterance: text,
            recentTranscript: Array(transcript.recent(now: u.endedAt).dropLast()),
            history: transcript.history,
            screenshotJPEG: shot,
            typedByUser: false
        )
        await answer(ctx, id: id, startedAt: u.endedAt)
    }

    /// Answers a heard utterance the pipeline skipped (too short or judged "not a question"), keeping its id.
    public func answer(utteranceId id: UUID) async {
        guard let index = skipped.firstIndex(where: { $0.id == id }) else { return }
        let text = skipped.remove(at: index).text
        continuation.yield(.activity(id: id, .thinking))
        let start = now()
        let ctx = AnswerContext(
            utterance: text,
            recentTranscript: transcript.recent(now: start),
            history: transcript.history,
            screenshotJPEG: try? await screenshots.captureJPEG(),
            typedByUser: true
        )
        await answer(ctx, id: id, startedAt: start)
    }

    /// Answers the most recent skipped utterance; false when there is none.
    @discardableResult
    public func answerLastSkipped() async -> Bool {
        guard let last = skipped.last else { return false }
        await answer(utteranceId: last.id)
        return true
    }

    private func remember(_ id: UUID, _ text: String) {
        skipped.append((id, text))
        if skipped.count > 20 { skipped.removeFirst(skipped.count - 20) }
    }

    public func ask(_ typed: String) async {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = UUID()
        let start = now()
        continuation.yield(.activity(id: id, .asked(text)))
        continuation.yield(.activity(id: id, .thinking))
        let ctx = AnswerContext(
            utterance: text,
            recentTranscript: transcript.recent(now: start),
            history: transcript.history,
            screenshotJPEG: try? await screenshots.captureJPEG(),
            typedByUser: true
        )
        await answer(ctx, id: id, startedAt: start)
    }

    /// One content block of a streamed round, rebuilt so the assistant turn can be replayed verbatim.
    private enum RoundBlock {
        case text(String)
        case thinking(text: String, signature: String)
        case redacted(String)
        case tool(id: String, name: String, json: String)
    }

    private func answer(_ ctx: AnswerContext, id: UUID, startedAt: Date) async {
        let kb = await knowledge.payload()
        let tools = await knowledge.tools()
        var request = RequestBuilder.answer(ctx, kb: kb, tools: tools, model: model, style: style, generation: generation, maxOutput: maxOutput)
        var gate = AnswerGate()
        var started = false
        var fullText = ""
        var firstTextAt: Date?
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
                var blocks: [Int: RoundBlock] = [:]
                stopReason = nil
                for try await event in claude.streamMessage(request) {
                    switch event {
                    case .textDelta(let index, let t):
                        if case .text(let so)? = blocks[index] { blocks[index] = .text(so + t) } else { blocks[index] = .text(t) }
                        if roundText.isEmpty {
                            Self.log.info("claude first token \(self.now().timeIntervalSince(requestAt), format: .fixed(precision: 2))s")
                        }
                        roundText += t
                        switch gate.feed(t) {
                        case .suppressed:
                            Self.log.info("skipped: not a question")
                            if !ctx.typedByUser { remember(id, ctx.utterance) }
                            continuation.yield(.activity(id: id, .skipped(.notAQuestion)))
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
                        blocks[index] = .tool(id: toolId, name: name, json: "")
                    case .inputJSONDelta(let index, let part):
                        if case .tool(let toolId, let name, let json)? = blocks[index] { blocks[index] = .tool(id: toolId, name: name, json: json + part) }
                    case .thinkingStart(let index):
                        blocks[index] = .thinking(text: "", signature: "")
                    case .thinkingDelta(let index, let t):
                        if case .thinking(let so, let sig)? = blocks[index] { blocks[index] = .thinking(text: so + t, signature: sig) }
                    case .signatureDelta(let index, let part):
                        if case .thinking(let so, let sig)? = blocks[index] { blocks[index] = .thinking(text: so, signature: sig + part) }
                    case .redactedThinking(let index, let data):
                        blocks[index] = .redacted(data)
                    case .messageDelta(let reason):
                        stopReason = reason
                    default:
                        break
                    }
                }
                let hasTools = blocks.values.contains { if case .tool = $0 { true } else { false } }
                guard stopReason == "tool_use", hasTools, round < Self.maxToolRounds else { break }
                continuation.yield(.kbLookup(id: id))
                // Replay the whole assistant turn in its original order, thinking blocks included.
                var assistant: [ContentBlock] = []
                var results: [ContentBlock] = []
                for index in blocks.keys.sorted() {
                    switch blocks[index]! {
                    case .text(let t):
                        assistant.append(.text(t))
                    case .thinking(let t, let sig):
                        assistant.append(.thinking(text: t, signature: sig))
                    case .redacted(let data):
                        assistant.append(.redactedThinking(data: data))
                    case .tool(let toolId, let name, let json):
                        let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .object([:])
                        assistant.append(.toolUse(id: toolId, name: name, input: input))
                        results.append(.toolResult(toolUseId: toolId, content: await knowledge.execute(tool: name, input: input)))
                    }
                }
                request = RequestBuilder.continuing(request, assistant: assistant, toolResults: results)
            }
        } catch {
            Self.log.error("answer failed: \(String(describing: error), privacy: .public)")
            start()
            continuation.yield(.answerFailed(id: id, message: Self.message(for: error)))
            return
        }

        guard started, let firstTextAt else {
            if stopReason == "refusal" {
                start()
                continuation.yield(.answerFailed(id: id, message: "Модель отказалась отвечать."))
            } else {
                if !ctx.typedByUser { remember(id, ctx.utterance) }
                continuation.yield(.activity(id: id, .skipped(.notAQuestion)))
            }
            return
        }
        let latency = Latency(timeToFirstToken: firstTextAt.timeIntervalSince(startedAt))
        Self.log.info("answer first text \(latency.timeToFirstToken, format: .fixed(precision: 2))s")
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
