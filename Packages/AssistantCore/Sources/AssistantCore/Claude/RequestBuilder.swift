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
    public struct Thinking: Encodable, Equatable, Sendable { public var type = "disabled" }
    public struct OutputConfig: Encodable, Equatable, Sendable { public var effort = "low" }

    public var model: String
    public var maxTokens: Int
    public var stream: Bool
    public var system: [ContentBlock]
    public var messages: [Message]
    public var tools: [ToolDefinition]?
    public var thinking = Thinking()
    public var outputConfig = OutputConfig()

    enum CodingKeys: String, CodingKey {
        case model, stream, system, messages, tools, thinking
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
    public static let model = "claude-haiku-5-5"
    static let maxTokens = 2048

    public static func answer(_ ctx: AnswerContext, kb: KBPayload, tools: [ToolDefinition]) -> MessagesRequest {
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
            model: model,
            maxTokens: maxTokens,
            stream: true,
            system: system(kb),
            messages: [Message(role: .user, content: content)],
            tools: tools.isEmpty ? nil : tools
        )
    }

    public static func continuing(_ request: MessagesRequest, assistant: [ContentBlock], toolResults: [ContentBlock]) -> MessagesRequest {
        var next = request
        next.messages.append(Message(role: .assistant, content: assistant))
        next.messages.append(Message(role: .user, content: toolResults))
        return next
    }

    public static func prewarm(kb: KBPayload, tools: [ToolDefinition]) -> MessagesRequest {
        var content = kbBlocks(kb)
        content.append(.text("<current_utterance>\n\n</current_utterance>"))
        return MessagesRequest(
            model: model,
            maxTokens: 0,
            stream: false,
            system: system(kb),
            messages: [Message(role: .user, content: content)],
            tools: tools.isEmpty ? nil : tools
        )
    }

    public static func countTokens(kb: [ContentBlock]) -> CountTokensRequest {
        CountTokensRequest(model: model, system: [], messages: [Message(role: .user, content: kb)], tools: nil)
    }

    private static func system(_ kb: KBPayload) -> [ContentBlock] {
        if case .inline = kb { return [.text(SystemPrompt.text)] }
        return [.text(SystemPrompt.text, cache: .oneHour)]
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
