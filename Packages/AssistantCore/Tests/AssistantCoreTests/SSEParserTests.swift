import Testing
@testable import AssistantCore

@Test func parsesTextDelta() throws {
    let e = try SSEParser.parse(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#)
    #expect(e == .textDelta(index: 0, text: "Hello"))
}

@Test func parsesToolUseStartAndJSONDelta() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t1","name":"search_kb","input":{}}}"#) == .toolUseStart(index: 1, id: "t1", name: "search_kb"))
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q"}}"#) == .inputJSONDelta(index: 1, partialJSON: #"{"q"#))
}

@Test func textBlockStartIsIgnored() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#) == nil)
}

@Test func parsesMessageDeltaAndStart() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#) == .messageDelta(stopReason: "end_turn"))
    #expect(try SSEParser.parse(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":3}}}"#) == .messageStart)
}

@Test func parsesStopAndPing() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"content_block_stop","index":2}"#) == .blockStop(index: 2))
    #expect(try SSEParser.parse(line: #"data: {"type":"message_stop"}"#) == .messageStop)
    #expect(try SSEParser.parse(line: #"data: {"type":"ping"}"#) == .ping)
}

@Test func parsesErrorEvent() throws {
    #expect(try SSEParser.parse(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .error(type: "overloaded_error", message: "Overloaded"))
}

@Test func ignoresEventAndBlankLines() throws {
    #expect(try SSEParser.parse(line: "event: ping") == nil)
    #expect(try SSEParser.parse(line: "") == nil)
    #expect(try SSEParser.parse(line: #"data: {"type":"something_new"}"#) == nil)
}
