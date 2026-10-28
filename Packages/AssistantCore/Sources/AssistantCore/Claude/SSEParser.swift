import Foundation

public enum SSEEvent: Equatable, Sendable {
    case messageStart
    case textDelta(index: Int, text: String)
    case toolUseStart(index: Int, id: String, name: String)
    case inputJSONDelta(index: Int, partialJSON: String)
    case thinkingStart(index: Int)
    case thinkingDelta(index: Int, text: String)
    case signatureDelta(index: Int, signature: String)
    case redactedThinking(index: Int, data: String)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?)
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
            return .messageStart
        case "content_block_start":
            guard let b = e.contentBlock else { return nil }
            switch b.type {
            case "tool_use": return .toolUseStart(index: e.index ?? 0, id: b.id ?? "", name: b.name ?? "")
            case "thinking": return .thinkingStart(index: e.index ?? 0)
            case "redacted_thinking": return .redactedThinking(index: e.index ?? 0, data: b.data ?? "")
            default: return nil
            }
        case "content_block_delta":
            switch e.delta?.type {
            case "text_delta": return .textDelta(index: e.index ?? 0, text: e.delta?.text ?? "")
            case "input_json_delta": return .inputJSONDelta(index: e.index ?? 0, partialJSON: e.delta?.partialJson ?? "")
            case "thinking_delta": return .thinkingDelta(index: e.index ?? 0, text: e.delta?.thinking ?? "")
            case "signature_delta": return .signatureDelta(index: e.index ?? 0, signature: e.delta?.signature ?? "")
            default: return nil
            }
        case "content_block_stop":
            return .blockStop(index: e.index ?? 0)
        case "message_delta":
            return .messageDelta(stopReason: e.delta?.stopReason)
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
        struct Block: Decodable { var type: String; var id: String?; var name: String?; var data: String? }
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var partialJson: String?
            var stopReason: String?
            var thinking: String?
            var signature: String?
            enum CodingKeys: String, CodingKey {
                case type, text, thinking, signature
                case partialJson = "partial_json"
                case stopReason = "stop_reason"
            }
        }
        struct ErrorInfo: Decodable { var type: String?; var message: String? }

        var type: String
        var index: Int?
        var contentBlock: Block?
        var delta: Delta?
        var error: ErrorInfo?

        enum CodingKeys: String, CodingKey {
            case type, index, delta, error
            case contentBlock = "content_block"
        }
    }
}
