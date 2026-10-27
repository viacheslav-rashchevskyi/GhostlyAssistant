import Foundation

public enum SSEEvent: Equatable, Sendable {
    case messageStart(inputTokens: Int, cacheReadTokens: Int)
    case textDelta(index: Int, text: String)
    case toolUseStart(index: Int, id: String, name: String)
    case inputJSONDelta(index: Int, partialJSON: String)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, outputTokens: Int)
    case messageStop
    case ping
    case error(type: String, message: String)
}

public enum SSEParser {
    /// Parses one line of a Messages API event stream. Returns nil for lines that carry no event.
    public static func parse(line: String) throws -> SSEEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        let e = try JSONDecoder().decode(Wire.self, from: Data(json.utf8))
        switch e.type {
        case "message_start":
            let u = e.message?.usage
            return .messageStart(inputTokens: u?.inputTokens ?? 0, cacheReadTokens: u?.cacheReadInputTokens ?? 0)
        case "content_block_start":
            guard let b = e.contentBlock, b.type == "tool_use" else { return nil }
            return .toolUseStart(index: e.index ?? 0, id: b.id ?? "", name: b.name ?? "")
        case "content_block_delta":
            switch e.delta?.type {
            case "text_delta": return .textDelta(index: e.index ?? 0, text: e.delta?.text ?? "")
            case "input_json_delta": return .inputJSONDelta(index: e.index ?? 0, partialJSON: e.delta?.partialJson ?? "")
            default: return nil
            }
        case "content_block_stop":
            return .blockStop(index: e.index ?? 0)
        case "message_delta":
            return .messageDelta(stopReason: e.delta?.stopReason, outputTokens: e.usage?.outputTokens ?? 0)
        case "message_stop":
            return .messageStop
        case "ping":
            return .ping
        case "error":
            return .error(type: e.error?.type ?? "unknown", message: e.error?.message ?? "")
        default:
            return nil
        }
    }

    private struct Wire: Decodable {
        struct Usage: Decodable {
            var inputTokens: Int?
            var outputTokens: Int?
            var cacheReadInputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }
        struct MessageInfo: Decodable { var usage: Usage? }
        struct Block: Decodable { var type: String; var id: String?; var name: String? }
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var partialJson: String?
            var stopReason: String?
            enum CodingKeys: String, CodingKey {
                case type, text
                case partialJson = "partial_json"
                case stopReason = "stop_reason"
            }
        }
        struct ErrorInfo: Decodable { var type: String?; var message: String? }

        var type: String
        var index: Int?
        var message: MessageInfo?
        var contentBlock: Block?
        var delta: Delta?
        var usage: Usage?
        var error: ErrorInfo?

        enum CodingKeys: String, CodingKey {
            case type, index, message, delta, usage, error
            case contentBlock = "content_block"
        }
    }
}
