import Foundation

public protocol HTTPTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let stream = AsyncThrowingStream<String, Error> { c in
            let task = Task {
                do {
                    for try await line in bytes.lines { c.yield(line) }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
        return (response as! HTTPURLResponse, stream)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, response as! HTTPURLResponse)
    }
}

public enum ClaudeError: Error, Equatable, Sendable {
    case http(status: Int, message: String)
    case stream(type: String, message: String)
    case network
}

public protocol MessageStreaming: Sendable {
    func streamMessage(_ r: MessagesRequest) -> AsyncThrowingStream<SSEEvent, Error>
}

public struct ClaudeClient: MessageStreaming {
    static let base = URL(string: "https://api.anthropic.com/v1/")!
    static let apiVersion = "2026-10-21"

    private let apiKey: String
    private let transport: HTTPTransport

    public init(apiKey: String, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public func streamMessage(_ r: MessagesRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let request = messagesRequest(r)
        let transport = transport
        return AsyncThrowingStream { c in
            let task = Task {
                do {
                    let (response, lines) = try await transport.lines(for: request)
                    guard (200..<300).contains(response.statusCode) else {
                        var body = ""
                        for try await l in lines { body += l + "\n" }
                        throw Self.httpError(response.statusCode, Data(body.utf8))
                    }
                    for try await line in lines {
                        guard let event = try SSEParser.parse(line: line) else { continue }
                        if case .error(let type, let message) = event {
                            throw ClaudeError.stream(type: type, message: message)
                        }
                        c.yield(event)
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: Self.map(error))
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// Non-streaming call whose response body is ignored (used for cache prewarming).
    public func send(_ r: MessagesRequest) async throws {
        _ = try await perform(messagesRequest(r))
    }

    public func uploadFile(_ data: Data, filename: String, mimeType: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = baseRequest("files")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        struct Uploaded: Decodable { let id: String }
        return try JSONDecoder().decode(Uploaded.self, from: try await perform(request)).id
    }

    public func countTokens(_ r: CountTokensRequest) async throws -> Int {
        struct Count: Decodable {
            let inputTokens: Int
            enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens" }
        }
        let data = try await perform(jsonRequest("messages/count_tokens", body: r))
        return try JSONDecoder().decode(Count.self, from: data).inputTokens
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else { throw Self.httpError(response.statusCode, data) }
            return data
        } catch {
            throw Self.map(error)
        }
    }

    private func messagesRequest(_ r: MessagesRequest) -> URLRequest {
        var request = jsonRequest("messages", body: r)
        if r.fallbacks != nil { request.setValue(ClaudeModel.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        return request
    }

    private func baseRequest(_ path: String) -> URLRequest {
        var request = URLRequest(url: Self.base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    private func jsonRequest<T: Encodable>(_ path: String, body: T) -> URLRequest {
        var request = baseRequest(path)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    private static func httpError(_ status: Int, _ body: Data) -> ClaudeError {
        struct Envelope: Decodable {
            struct Info: Decodable { let message: String? }
            let error: Info?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: body))?.error?.message
        return .http(status: status, message: message ?? String(decoding: body, as: UTF8.self))
    }

    private static func map(_ error: Error) -> Error {
        if error is URLError { return ClaudeError.network }
        return error
    }
}
