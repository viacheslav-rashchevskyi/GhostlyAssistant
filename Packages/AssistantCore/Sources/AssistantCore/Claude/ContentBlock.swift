import Foundation

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

public enum CacheTTL: String, Codable, Sendable {
    case fiveMinutes = "5m"
    case oneHour = "1h"
}

public enum ContentBlock: Codable, Equatable, Sendable {
    case text(String, cache: CacheTTL? = nil)
    case imageJPEG(Data)
    case imagePNG(Data)
    case document(fileId: String, title: String, cache: CacheTTL? = nil)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: [ContentBlock], isError: Bool = false)

    private enum Key: String, CodingKey {
        case type, text, source, title, id, name, input, content
        case cacheControl = "cache_control"
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    private struct CacheControl: Codable {
        var type = "ephemeral"
        var ttl: CacheTTL
    }

    private struct Source: Codable {
        var type: String
        var mediaType: String?
        var data: String?
        var fileId: String?

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
            case fileId = "file_id"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .text(let text, let cache):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(cache.map { CacheControl(ttl: $0) }, forKey: .cacheControl)
        case .imageJPEG(let data), .imagePNG(let data):
            let mime = if case .imagePNG = self { "image/png" } else { "image/jpeg" }
            try c.encode("image", forKey: .type)
            try c.encode(Source(type: "base64", mediaType: mime, data: data.base64EncodedString()), forKey: .source)
        case .document(let fileId, let title, let cache):
            try c.encode("document", forKey: .type)
            try c.encode(Source(type: "file", fileId: fileId), forKey: .source)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(cache.map { CacheControl(ttl: $0) }, forKey: .cacheControl)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .toolUseId)
            try c.encode(content, forKey: .content)
            if isError { try c.encode(true, forKey: .isError) }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text),
                         cache: try c.decodeIfPresent(CacheControl.self, forKey: .cacheControl)?.ttl)
        case "image":
            let s = try c.decode(Source.self, forKey: .source)
            let data = Data(base64Encoded: s.data ?? "") ?? Data()
            self = s.mediaType == "image/png" ? .imagePNG(data) : .imageJPEG(data)
        case "document":
            let s = try c.decode(Source.self, forKey: .source)
            self = .document(fileId: s.fileId ?? "", title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                             cache: try c.decodeIfPresent(CacheControl.self, forKey: .cacheControl)?.ttl)
        case "tool_use":
            self = .toolUse(id: try c.decode(String.self, forKey: .id),
                            name: try c.decode(String.self, forKey: .name),
                            input: try c.decode(JSONValue.self, forKey: .input))
        case "tool_result":
            self = .toolResult(toolUseId: try c.decode(String.self, forKey: .toolUseId),
                               content: try c.decodeIfPresent([ContentBlock].self, forKey: .content) ?? [],
                               isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown block type \(type)")
        }
    }
}

public struct Message: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var role: Role
    public var content: [ContentBlock]

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}
