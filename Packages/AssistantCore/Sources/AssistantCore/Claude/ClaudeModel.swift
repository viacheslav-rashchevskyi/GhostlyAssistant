import Foundation

/// Price per million tokens: base input, output, cache hits and 1-hour cache writes (nil when unknown).
public struct ClaudePrice: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double?
    public let cacheWrite: Double?

    public init(input: Double, output: Double, cacheRead: Double? = nil, cacheWrite: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
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

    /// Base, output, cache-hit and 1-hour cache-write prices from Anthropic's pricing page.
    private static let prices: [String: ClaudePrice] = [
        "claude-fable-5-1": ClaudePrice(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 20),
        "claude-fable-5": ClaudePrice(input: 10, output: 50, cacheRead: 1, cacheWrite: 20),
        "claude-mythos-5-1": ClaudePrice(input: 10, output: 50, cacheRead: 0.25, cacheWrite: 20),
        "claude-opus-5-5": ClaudePrice(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 8),
        "claude-opus-5": ClaudePrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 10),
        "claude-opus-4-8": ClaudePrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 10),
        "claude-opus-4-7": ClaudePrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 10),
        "claude-opus-4-6": ClaudePrice(input: 5, output: 25, cacheRead: 0.5, cacheWrite: 10),
        "claude-sonnet-5-5": ClaudePrice(input: 2, output: 10, cacheRead: 0.1, cacheWrite: 4),
        "claude-sonnet-5": ClaudePrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 4),
        "claude-sonnet-4-6": ClaudePrice(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 6),
        "claude-haiku-5-5": ClaudePrice(input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.2),
        "claude-haiku-4-5": ClaudePrice(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 2)
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
