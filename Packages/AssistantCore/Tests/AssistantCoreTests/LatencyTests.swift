import Testing
@testable import AssistantCore

@Test func latencyLabelUsesCommaDecimal() {
    #expect(Latency(timeToFirstToken: 0.84, tokensPerSecond: 140.4).label == "0,8 с · 140 ток/с")
    #expect(Latency(timeToFirstToken: 1.25, tokensPerSecond: nil).label == "1,3 с")
}

@Test func pluralForms() {
    #expect(RussianPlural.previousAnswers(1) == "↑ ещё 1 предыдущий ответ")
    #expect(RussianPlural.previousAnswers(3) == "↑ ещё 3 предыдущих ответа")
    #expect(RussianPlural.previousAnswers(5) == "↑ ещё 5 предыдущих ответов")
    #expect(RussianPlural.previousAnswers(12) == "↑ ещё 12 предыдущих ответов")
    #expect(RussianPlural.previousAnswers(22) == "↑ ещё 22 предыдущих ответа")
    #expect(RussianPlural.previousAnswers(21) == "↑ ещё 21 предыдущий ответ")
}
