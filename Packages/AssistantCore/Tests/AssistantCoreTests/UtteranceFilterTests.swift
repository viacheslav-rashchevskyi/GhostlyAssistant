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

@Test func russianAndEnglishHallucinationsAreDropped() {
    #expect(!UtteranceFilter.shouldSend("Продолжение следует..."))
    #expect(!UtteranceFilter.shouldSend("Субтитры сделал DimaTorzok"))
    #expect(!UtteranceFilter.shouldSend("Редактор субтитров А.Синецкая Корректор А.Егорова"))
    #expect(!UtteranceFilter.shouldSend("Спасибо за просмотр!"))
    #expect(!UtteranceFilter.shouldSend("Thanks for watching!"))
}

@Test func realRussianQuestionsStillPass() {
    #expect(UtteranceFilter.shouldSend("Почему вы выбрали именно этот алгоритм?"))
}

@Test func wordsJoinedByPunctuationCountSeparately() {
    #expect(UtteranceFilter.shouldSend("почему,зачем,как это работает"))
}
