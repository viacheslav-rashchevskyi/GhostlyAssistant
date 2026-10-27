import Testing
@testable import AssistantCore

@Test func shortUtterancesAreDropped() {
    #expect(!UtteranceFilter.shouldSend("так, добре"))
    #expect(UtteranceFilter.shouldSend("чому ви обрали Swift?"))
}

@Test func hallucinationsAreDropped() {
    #expect(!UtteranceFilter.shouldSend("Дякую за перегляд!"))
    #expect(!UtteranceFilter.shouldSend("Субтитри зроблені спільнотою Amara.org"))
    #expect(!UtteranceFilter.shouldSend("Thank you for watching."))
    #expect(!UtteranceFilter.shouldSend("Продовження далі..."))
}
