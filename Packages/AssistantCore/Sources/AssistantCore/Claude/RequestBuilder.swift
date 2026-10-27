import Foundation

public struct QAPair: Equatable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

public struct AnswerContext: Equatable, Sendable {
    public var utterance: String
    public var recentTranscript: [String]
    public var history: [QAPair]
    public var screenshotJPEG: Data?
    public var typedByUser: Bool

    public init(utterance: String, recentTranscript: [String], history: [QAPair], screenshotJPEG: Data?, typedByUser: Bool) {
        self.utterance = utterance
        self.recentTranscript = recentTranscript
        self.history = history
        self.screenshotJPEG = screenshotJPEG
        self.typedByUser = typedByUser
    }
}

public enum KBPayload: Equatable, Sendable {
    case none
    case inline([ContentBlock])
    case search
}

public struct ToolDefinition: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

public struct MessagesRequest: Encodable, Equatable, Sendable {
    public struct Thinking: Encodable, Equatable, Sendable { public var type: String }
    public struct OutputConfig: Encodable, Equatable, Sendable { public var effort: String }

    public var model: String
    public var maxTokens: Int
    public var stream: Bool
    public var system: [ContentBlock]
    public var messages: [Message]
    public var tools: [ToolDefinition]?
    public var thinking: Thinking?
    public var outputConfig: OutputConfig?
    public var fallbacks: String?

    enum CodingKeys: String, CodingKey {
        case model, stream, system, messages, tools, thinking, fallbacks
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

public struct CountTokensRequest: Encodable, Equatable, Sendable {
    public var model: String
    public var system: [ContentBlock]
    public var messages: [Message]
    public var tools: [ToolDefinition]?
}

public enum RequestBuilder {
    static let maxTokens = 2048

    public static func answer(_ ctx: AnswerContext, kb: KBPayload, tools: [ToolDefinition], model: ClaudeModel = .haiku, style: AnswerStyle = AnswerStyle()) -> MessagesRequest {
        var content = kbBlocks(kb)
        if !ctx.recentTranscript.isEmpty {
            content.append(.text("<recent_transcript>\n\(ctx.recentTranscript.joined(separator: "\n"))\n</recent_transcript>"))
        }
        if !ctx.history.isEmpty {
            let pairs = ctx.history.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n")
            content.append(.text("<previous_answers>\n\(pairs)\n</previous_answers>"))
        }
        if let shot = ctx.screenshotJPEG {
            content.append(.imageJPEG(shot))
        }
        let tag = ctx.typedByUser ? "typed_question" : "current_utterance"
        content.append(.text("<\(tag)>\n\(ctx.utterance)\n</\(tag)>"))
        return MessagesRequest(
            model: model.id,
            maxTokens: maxTokens,
            stream: true,
            system: system(kb, style: style),
            messages: [Message(role: .user, content: content)],
            tools: tools.isEmpty ? nil : tools,
            thinking: model.thinking,
            outputConfig: model.effort.map { MessagesRequest.OutputConfig(effort: $0) },
            fallbacks: model.fallbacks
        )
    }

    public static func continuing(_ request: MessagesRequest, assistant: [ContentBlock], toolResults: [ContentBlock]) -> MessagesRequest {
        var next = request
        next.messages.append(Message(role: .assistant, content: assistant))
        next.messages.append(Message(role: .user, content: toolResults))
        return next
    }

    public static func prewarm(kb: KBPayload, tools: [ToolDefinition], model: ClaudeModel = .haiku) -> MessagesRequest {
        var content = kbBlocks(kb)
        content.append(.text("<current_utterance>\n\n</current_utterance>"))
        return MessagesRequest(
            model: model.id,
            maxTokens: 0,
            stream: false,
            system: system(kb),
            messages: [Message(role: .user, content: content)],
            tools: tools.isEmpty ? nil : tools,
            thinking: model.thinking,
            outputConfig: model.effort.map { MessagesRequest.OutputConfig(effort: $0) },
            fallbacks: model.fallbacks
        )
    }

    public static func countTokens(kb: [ContentBlock], model: ClaudeModel = .haiku) -> CountTokensRequest {
        CountTokensRequest(model: model.id, system: [], messages: [Message(role: .user, content: kb)], tools: nil)
    }

    private static func system(_ kb: KBPayload, style: AnswerStyle = AnswerStyle()) -> [ContentBlock] {
        let cacheBase: CacheTTL? = { if case .inline = kb { nil } else { .oneHour } }()
        guard let instruction = style.instruction else {
            return [.text(SystemPrompt.text, cache: cacheBase)]
        }
        // The style block is last, so it carries the cache marker and the prompt stays a stable cached prefix.
        return [.text(SystemPrompt.text), .text(instruction, cache: cacheBase)]
    }

    private static func kbBlocks(_ kb: KBPayload) -> [ContentBlock] {
        guard case .inline(var blocks) = kb, let last = blocks.popLast() else { return [] }
        return blocks + [withCache(last)]
    }

    private static func withCache(_ block: ContentBlock) -> ContentBlock {
        switch block {
        case .text(let t, _): .text(t, cache: .oneHour)
        case .document(let id, let title, _): .document(fileId: id, title: title, cache: .oneHour)
        default: block
        }
    }
}
