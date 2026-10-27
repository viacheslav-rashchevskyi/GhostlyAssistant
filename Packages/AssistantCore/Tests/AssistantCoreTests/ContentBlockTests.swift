import Foundation
import Testing
@testable import AssistantCore

@Test func textBlockEncodesCacheControl() throws {
    let json = try encodeToDict(ContentBlock.text("kb", cache: .oneHour))
    #expect(json["type"] as? String == "text")
    #expect(json["text"] as? String == "kb")
    #expect((json["cache_control"] as? [String: String]) == ["type": "ephemeral", "ttl": "1h"])
}

@Test func plainTextHasNoCacheControl() throws {
    #expect(try encodeToDict(ContentBlock.text("x"))["cache_control"] == nil)
}

@Test func imageEncodesBase64Source() throws {
    let json = try encodeToDict(ContentBlock.imageJPEG(Data([1, 2, 3])))
    #expect(json["type"] as? String == "image")
    let source = json["source"] as! [String: String]
    #expect(source == ["type": "base64", "media_type": "image/jpeg", "data": "AQID"])
}

@Test func documentEncodesFileSource() throws {
    let json = try encodeToDict(ContentBlock.document(fileId: "file_1", title: "a.pdf"))
    #expect(json["type"] as? String == "document")
    #expect((json["source"] as? [String: String]) == ["type": "file", "file_id": "file_1"])
    #expect(json["title"] as? String == "a.pdf")
}

@Test func toolResultEncodesContentAndOmitsFalseError() throws {
    let json = try encodeToDict(ContentBlock.toolResult(toolUseId: "t1", content: [.text("hit")]))
    #expect(json["type"] as? String == "tool_result")
    #expect(json["tool_use_id"] as? String == "t1")
    #expect(json["is_error"] == nil)
    #expect((json["content"] as? [[String: Any]])?.first?["text"] as? String == "hit")
}

@Test func toolUseRoundTrips() throws {
    let b = ContentBlock.toolUse(id: "t1", name: "search_kb", input: .object(["query": .string("кеш")]))
    #expect(try JSONDecoder().decode(ContentBlock.self, from: JSONEncoder().encode(b)) == b)
}

@Test func messageEncodesRole() throws {
    let json = try encodeToDict(Message(role: .assistant, content: [.text("a")]))
    #expect(json["role"] as? String == "assistant")
}

@Test func inlinePDFEncodesBase64Source() throws {
    let json = try encodeToDict(ContentBlock.pdf(Data([1, 2, 3]), title: "a.pdf"))
    #expect(json["type"] as? String == "document")
    #expect((json["source"] as? [String: String]) == ["type": "base64", "media_type": "application/pdf", "data": "AQID"])
    #expect(json["title"] as? String == "a.pdf")
}
