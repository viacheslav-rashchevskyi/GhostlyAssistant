import Foundation
import Testing
@testable import AssistantCore

@Test func loadsSupportedFormats() throws {
    let r = KnowledgeLoader.load([try KnowledgeFixtures.makeDir()])
    #expect(Set(r.documents.map(\.kind)) == [.pdf, .docx, .text, .image])
    let pdf = try #require(r.documents.first { $0.kind == .pdf })
    #expect(pdf.title == "report.pdf")
    #expect(pdf.pages.count == 2)
    #expect(pdf.pages[1].contains("кешування"))
    #expect(try #require(r.documents.first { $0.kind == .docx }).pages[0].contains("Вступ"))
    #expect(r.documents.filter { $0.kind == .text }.map(\.title).sorted() == ["notes.md", "plain.txt"])
}

@Test func unreadableFilesAreSkipped() throws {
    let r = KnowledgeLoader.load([try KnowledgeFixtures.makeDir()])
    #expect(r.skipped.map(\.url.lastPathComponent).sorted() == ["broken.pdf", "notes.xyz"])
}

@Test func emptyFolderGivesNoDocuments() throws {
    let r = KnowledgeLoader.load([try KnowledgeFixtures.makeEmptyDir()])
    #expect(r.documents.isEmpty)
    #expect(r.skipped.isEmpty)
}

@Test func singleFileCanBeChosen() throws {
    let dir = try KnowledgeFixtures.makeDir()
    let r = KnowledgeLoader.load([dir.appendingPathComponent("notes.md")])
    #expect(r.documents.map(\.title) == ["notes.md"])
}
