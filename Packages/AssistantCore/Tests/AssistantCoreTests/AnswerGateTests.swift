import Testing
@testable import AssistantCore

@Test func gateWaitsOnWhitespace() {
    var g = AnswerGate()
    #expect(g.feed("  \n") == .undecided)
}

@Test func gateSuppressesSentinelWithNoise() {
    var g = AnswerGate()
    #expect(g.feed("\n∅.") == .suppressed)
    #expect(g.feed("more") == .suppressed)
}

@Test func gateEmitsAnswerTrimmingLeadingWhitespace() {
    var g = AnswerGate()
    #expect(g.feed(" ") == .undecided)
    #expect(g.feed("Бо дані") == .emit("Бо дані"))
    #expect(g.feed(" і ∅ всередині") == .emit(" і ∅ всередині"))
}

@Test func gateSuppressesSentinelWrappedInMarkdown() {
    var g = AnswerGate()
    #expect(g.feed("**∅**") == .suppressed)
    var g2 = AnswerGate()
    #expect(g2.feed("*") == .undecided)
    #expect(g2.feed("*∅") == .suppressed)
}

@Test func gateStillEmitsBoldAnswers() {
    var g = AnswerGate()
    #expect(g.feed("**Бо") == .emit("**Бо"))
}
