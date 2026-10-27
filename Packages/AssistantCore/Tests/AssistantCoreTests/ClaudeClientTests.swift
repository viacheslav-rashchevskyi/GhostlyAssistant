import Foundation
import Testing
@testable import AssistantCore

final class MockTransport: HTTPTransport, @unchecked Sendable {
    let status: Int
    let lines: [String]
    let body: String
    private(set) var last: URLRequest?

    init(status: Int, lines: [String] = [], body: String = "") {
        self.status = status
        self.lines = lines
        self.body = body
    }

    private func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        last = request
        let source = status == 200 ? lines : body.components(separatedBy: "\n")
        return (response(for: request), AsyncThrowingStream { c in
            for l in source { c.yield(l) }
            c.finish()
        })
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        last = request
        return (Data(body.utf8), response(for: request))
    }
}

private let sampleRequest = RequestBuilder.answer(
    AnswerContext(utterance: "Хто?", recentTranscript: [], history: [], screenshotJPEG: nil, typedByUser: false),
    kb: .none, tools: []
)

@Test func streamSendsHeadersAndYieldsEvents() async throws {
    let t = MockTransport(status: 200, lines: [
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#,
        "",
        #"data: {"type":"message_stop"}"#
    ])
    var got: [SSEEvent] = []
    for try await e in ClaudeClient(apiKey: "k", transport: t).streamMessage(sampleRequest) { got.append(e) }
    #expect(got == [.textDelta(index: 0, text: "Hi"), .messageStop])
    #expect(t.last?.value(forHTTPHeaderField: "x-api-key") == "k")
    #expect(t.last?.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
    #expect(t.last?.httpMethod == "POST")
    #expect(t.last?.url?.absoluteString == "https://api.anthropic.com/v1/messages")
}

@Test func httpErrorIsMapped() async {
    let t = MockTransport(status: 401, body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
    await #expect(throws: ClaudeError.http(status: 401, message: "invalid x-api-key")) {
        for try await _ in ClaudeClient(apiKey: "k", transport: t).streamMessage(sampleRequest) {}
    }
}

@Test func streamErrorEventThrows() async {
    let t = MockTransport(status: 200, lines: [#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])
    await #expect(throws: ClaudeError.stream(type: "overloaded_error", message: "Overloaded")) {
        for try await _ in ClaudeClient(apiKey: "k", transport: t).streamMessage(sampleRequest) {}
    }
}

@Test func uploadReturnsFileId() async throws {
    let t = MockTransport(status: 200, body: #"{"id":"file_abc"}"#)
    let id = try await ClaudeClient(apiKey: "k", transport: t).uploadFile(Data("pdf".utf8), filename: "a.pdf", mimeType: "application/pdf")
    #expect(id == "file_abc")
    #expect(t.last?.url?.absoluteString == "https://api.anthropic.com/v1/files")
    #expect(String(decoding: t.last!.httpBody!, as: UTF8.self).contains(#"name="file"; filename="a.pdf""#))
}

@Test func countTokensReadsInputTokens() async throws {
    let t = MockTransport(status: 200, body: #"{"input_tokens":1234}"#)
    #expect(try await ClaudeClient(apiKey: "k", transport: t).countTokens(RequestBuilder.countTokens(kb: [.text("x")])) == 1234)
    #expect(t.last?.url?.path == "/v1/messages/count_tokens")
}

@Test func sendMapsHTTPError() async {
    let t = MockTransport(status: 529, body: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
    await #expect(throws: ClaudeError.http(status: 529, message: "Overloaded")) {
        try await ClaudeClient(apiKey: "k", transport: t).send(sampleRequest)
    }
}
