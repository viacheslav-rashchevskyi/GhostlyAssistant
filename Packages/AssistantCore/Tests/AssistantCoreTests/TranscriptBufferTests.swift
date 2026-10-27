import Foundation
import Testing
@testable import AssistantCore

@Test func transcriptKeepsOnlyWindow() {
    var b = TranscriptBuffer()
    let t0 = Date(timeIntervalSince1970: 0)
    b.append("old", at: t0)
    b.append("new", at: t0 + 200)
    #expect(b.recent(now: t0 + 200) == ["new"])
}

@Test func historyKeepsLastThree() {
    var b = TranscriptBuffer()
    for i in 1...4 { b.addAnswer(QAPair(question: "\(i)", answer: "a")) }
    #expect(b.history.map(\.question) == ["2", "3", "4"])
}
