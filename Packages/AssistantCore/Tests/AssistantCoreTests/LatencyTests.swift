import Testing
@testable import AssistantCore

@Test func latencyLabelUsesUkrainianFormat() {
    #expect(Latency(timeToFirstToken: 0.84, tokensPerSecond: 140.4).label == "0,8 с · 140 ток/с")
    #expect(Latency(timeToFirstToken: 1.25, tokensPerSecond: nil).label == "1,3 с")
}

@Test func pluralForms() {
    #expect(UkrainianPlural.previousAnswers(1) == "↑ ще 1 попередня відповідь")
    #expect(UkrainianPlural.previousAnswers(3) == "↑ ще 3 попередні відповіді")
    #expect(UkrainianPlural.previousAnswers(5) == "↑ ще 5 попередніх відповідей")
    #expect(UkrainianPlural.previousAnswers(12) == "↑ ще 12 попередніх відповідей")
    #expect(UkrainianPlural.previousAnswers(22) == "↑ ще 22 попередні відповіді")
    #expect(UkrainianPlural.previousAnswers(21) == "↑ ще 21 попередня відповідь")
}
