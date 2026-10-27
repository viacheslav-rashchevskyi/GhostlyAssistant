import Foundation
import Testing
@testable import AssistantCore

let searchDocs = [
    KBDocument(url: URL(fileURLWithPath: "/kb/report.pdf"), kind: .pdf, title: "report.pdf",
               pages: ["Вступ і мета роботи.", "Розділ 3.2. Кешування LRU зменшило час відповіді на 60%."]),
    KBDocument(url: URL(fileURLWithPath: "/kb/notes.md"), kind: .text, title: "notes.md",
               pages: ["Список літератури."])
]

@Test func findsRelevantPage() {
    let hits = BM25Index(documents: searchDocs).search("кешування LRU")
    #expect(hits.first?.title == "report.pdf")
    #expect(hits.first?.page == 2)
}

@Test func caseAndPunctuationInsensitive() {
    #expect(BM25Index(documents: searchDocs).search("КЕШУВАННЯ!").first?.page == 2)
}

@Test func noMatchReturnsEmpty() {
    #expect(BM25Index(documents: searchDocs).search("квантова хромодинаміка").isEmpty)
}

@Test func longPagesAreSplitIntoChunksKeepingPageNumber() {
    let long = String(repeating: "слово ", count: 300) + "унікальний"
    let doc = KBDocument(url: URL(fileURLWithPath: "/kb/long.pdf"), kind: .pdf, title: "long.pdf", pages: ["перша", long])
    let hit = BM25Index(documents: [doc], chunkSize: 800).search("унікальний").first
    #expect(hit?.page == 2)
    #expect((hit?.snippet.count ?? 0) <= 800)
}
