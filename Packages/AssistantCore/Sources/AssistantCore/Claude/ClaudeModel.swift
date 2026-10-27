import Foundation

/// Price per million tokens, input / output.
public struct ClaudePrice: Equatable, Sendable {
    public let input: Double
    public let output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }

    /// For example "$0,10 / $0,50" or "$4 / $20".
    public var label: String { "\(Self.dollars(input)) / \(Self.dollars(output))" }

    private static func dollars(_ value: Double) -> String {
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
        return "$" + text.replacingOccurrences(of: ".", with: ",")
    }
}

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
    var thinking: MessagesRequest.Thinking? {
        switch id {
        case "claude-haiku-5-5", "claude-sonnet-5", "claude-opus-5": MessagesRequest.Thinking(type: "disabled")
        case "claude-sonnet-5-5": MessagesRequest.Thinking(type: "between_tools")
        default: nil
        }
    }

    /// Models that accept `output_config.effort`; others (Haiku 4.5 and older) return 400 if it is sent.
    var effort: String? {
        Self.effortModels.contains(id) ? "low" : nil
    }

    /// Server-side refusal fallback, available on the newest models only.
    var fallbacks: String? {
        Self.fallbackModels.contains(id) ? "default" : nil
    }

    /// Anthropic first-party rates; nil for models not in the table.
    public var price: ClaudePrice? {
        Self.prices[id]
    }

    static let fallbackBeta = "server-side-fallback-2026-07-01"

    private static let effortModels: Set<String> = [
        "claude-fable-5-1", "claude-fable-5", "claude-mythos-5-1", "claude-mythos-5",
        "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5-5"
    ]

    private static let fallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    private static let prices: [String: ClaudePrice] = [
        "claude-fable-5-1": ClaudePrice(input: 10, output: 50),
        "claude-fable-5": ClaudePrice(input: 10, output: 50),
        "claude-mythos-5-1": ClaudePrice(input: 10, output: 50),
        "claude-opus-5-5": ClaudePrice(input: 4, output: 20),
        "claude-opus-5": ClaudePrice(input: 5, output: 25),
        "claude-opus-4-8": ClaudePrice(input: 5, output: 25),
        "claude-opus-4-7": ClaudePrice(input: 5, output: 25),
        "claude-opus-4-6": ClaudePrice(input: 5, output: 25),
        "claude-sonnet-5-5": ClaudePrice(input: 2, output: 10),
        "claude-sonnet-5": ClaudePrice(input: 2, output: 10),
        "claude-sonnet-4-6": ClaudePrice(input: 3, output: 15),
        "claude-haiku-5-5": ClaudePrice(input: 0.10, output: 0.50),
        "claude-haiku-4-5": ClaudePrice(input: 1, output: 5)
    ]
}

/// One entry of `GET /v1/models`.
public struct ClaudeModelInfo: Equatable, Sendable, Identifiable, Decodable {
    public let id: String
    public let displayName: String
    public let createdAt: Date?

    public init(id: String, displayName: String, createdAt: Date?) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }

    public var model: ClaudeModel { ClaudeModel(id: id) }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}
