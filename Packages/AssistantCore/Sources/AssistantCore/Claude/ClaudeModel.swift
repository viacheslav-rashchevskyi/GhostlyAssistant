import Foundation

/// Any Claude model by API id, with the request settings it needs for a fast reply.
public struct ClaudeModel: Hashable, Sendable, Identifiable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public static let haiku = ClaudeModel(id: "claude-haiku-5-5")
    public static let sonnet = ClaudeModel(id: "claude-sonnet-5-5")
    public static let opus = ClaudeModel(id: "claude-opus-5-5")

    /// How to keep thinking out of the way. Haiku 5.5, Sonnet 5 and Opus 5 accept `disabled`; Sonnet 5.5 rejects
    /// it and uses `between_tools`; Fable, Opus 5.5 can't turn it off; older models simply don't think when
    /// the field is omitted.
    var offThinking: MessagesRequest.Thinking? {
        switch id {
        case "claude-haiku-5-5", "claude-sonnet-5", "claude-opus-5": MessagesRequest.Thinking(type: "disabled")
        case "claude-sonnet-5-5": MessagesRequest.Thinking(type: "between_tools")
        default: nil
        }
    }

    static let alwaysThinking: Set<String> = ["claude-fable-5-1", "claude-fable-5", "claude-mythos-5-1", "claude-mythos-5", "claude-opus-5-5"]

    /// Server-side refusal fallback, available on the newest models only.
    var fallbacks: String? {
        Self.fallbackModels.contains(id) ? "default" : nil
    }

    static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Models that accept `output_config.effort` and adaptive thinking; others (Haiku 4.5 and older) return 400.
    static let effortModels: Set<String> = [
        "claude-fable-5-1", "claude-fable-5", "claude-mythos-5-1", "claude-mythos-5",
        "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5-5"
    ]

    private static let fallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

}

/// One entry of `GET /v1/models`.
public struct ClaudeModelInfo: Equatable, Sendable, Identifiable, Decodable {
    public let id: String
    public let displayName: String
    public let createdAt: Date?
    /// The model's output cap; older API responses may leave it out.
    public let maxTokens: Int?

    public init(id: String, displayName: String, createdAt: Date?, maxTokens: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.maxTokens = maxTokens
    }

    public var model: ClaudeModel { ClaudeModel(id: id) }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
        case maxTokens = "max_tokens"
    }
}
