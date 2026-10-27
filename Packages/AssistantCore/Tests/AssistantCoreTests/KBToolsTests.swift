import Foundation
import Testing
@testable import AssistantCore

private func run(_ name: String, _ input: JSONValue) -> [ContentBlock] {
    KBTools.run(name: name, input: input, index: BM25Index(documents: searchDocs), documents: searchDocs)
}

@Test func toolDefinitionsAreSearchAndOpen() {
    #expect(KBTools.definitions.map(\.name) == ["search_kb", "open_page"])
}

@Test func searchToolFormatsHits() {
    guard case .text(let t, _) = run("search_kb", .object(["query": .string("кешування")])).first else { Issue.record(); return }
    #expect(t.contains("[report.pdf, p. 2]"))
    #expect(t.contains("LRU"))
}

@Test func searchWithoutHitsSaysSo() {
    #expect(run("search_kb", .object(["query": .string("хромодинаміка")])) == [.text("No matches in the knowledge base.")])
}

@Test func openTextPageReturnsText() {
    #expect(run("open_page", .object(["document": .string("notes.md"), "page": .number(1)])) == [.text("[notes.md, p. 1]\nСписок літератури.")])
}

@Test func openUnknownDocumentIsError() {
    #expect(run("open_page", .object(["document": .string("nope.pdf"), "page": .number(1)])) == [.text("Document not found: nope.pdf")])
}

@Test func openPageOutOfRangeIsError() {
    #expect(run("open_page", .object(["document": .string("notes.md"), "page": .number(5)])) == [.text("notes.md has 1 page(s).")])
}

@Test func openRealPDFPageIncludesImage() throws {
    let dir = try KnowledgeFixtures.makeDir()
    let docs = KnowledgeLoader.load([dir.appendingPathComponent("report.pdf")]).documents
    let out = KBTools.run(name: "open_page", input: .object(["document": .string("report.pdf"), "page": .number(2)]),
                          index: BM25Index(documents: docs), documents: docs)
    guard case .text(let t, _) = out.first else { Issue.record(); return }
    #expect(t.hasPrefix("[report.pdf, p. 2]\n"))
    #expect(out.contains { if case .imagePNG(let d) = $0 { !d.isEmpty } else { false } })
}

@Test func storeInSearchModeExposesAndRunsTools() async throws {
    let store = KnowledgeStore(api: FakeUploader(tokens: 80_001))
    _ = await store.configure([try KnowledgeFixtures.makeDir()])
    #expect(await store.tools().map(\.name) == ["search_kb", "open_page"])
    let out = await store.execute(tool: "search_kb", input: .object(["query": .string("кешування")]))
    guard case .text(let t, _) = out.first else { Issue.record(); return }
    #expect(t.contains("[report.pdf, p. 2]"))
}
