import Foundation
import Testing
@testable import AssistantCore

final class FakeUploader: KBUploading, @unchecked Sendable {
    let tokens: Int
    let fileId: String
    let uploadError: Error?
    private(set) var uploads: [String] = []
    private(set) var sent: [MessagesRequest] = []
    private(set) var counted: [CountTokensRequest] = []

    init(tokens: Int, fileId: String = "file_1", uploadError: Error? = nil) {
        self.tokens = tokens
        self.fileId = fileId
        self.uploadError = uploadError
    }

    func uploadFile(_ data: Data, filename: String, mimeType: String) async throws -> String {
        if let uploadError { throw uploadError }
        uploads.append(filename)
        return fileId
    }

    func countTokens(_ r: CountTokensRequest) async throws -> Int {
        counted.append(r)
        return tokens
    }

    func send(_ r: MessagesRequest) async throws { sent.append(r) }
}

private func texts(_ blocks: [ContentBlock]) -> [String] {
    blocks.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
}

@Test func smallKBIsInlineWithUploadedPDF() async throws {
    let api = FakeUploader(tokens: 5_000, fileId: "file_1")
    let store = KnowledgeStore(api: api)
    let cfg = await store.configure([try KnowledgeFixtures.makeDir()])
    #expect(cfg.mode == .inline)
    #expect(cfg.tokens == 5_000)
    #expect(cfg.skipped.sorted() == ["broken.pdf", "notes.xyz"])
    guard case .inline(let blocks) = await store.payload() else { Issue.record(); return }
    #expect(blocks.contains(.document(fileId: "file_1", title: "report.pdf")))
    #expect(texts(blocks).contains { $0.hasPrefix("### notes.md\n") && $0.contains("Список літератури.") })
    #expect(blocks.contains { if case .imagePNG = $0 { true } else { false } })
    #expect(api.uploads == ["report.pdf"])
    #expect(await store.tools().isEmpty)
}

@Test func inlineKBEndsWithACacheableBlock() async throws {
    let store = KnowledgeStore(api: FakeUploader(tokens: 100))
    _ = await store.configure([try KnowledgeFixtures.makeDir()])
    guard case .inline(let blocks) = await store.payload() else { Issue.record(); return }
    switch blocks.last {
    case .text, .document: break
    default: Issue.record("last block is not cacheable: \(String(describing: blocks.last))")
    }
}

@Test func largeKBSwitchesToSearch() async throws {
    let store = KnowledgeStore(api: FakeUploader(tokens: 80_001))
    #expect(await store.configure([try KnowledgeFixtures.makeDir()]).mode == .search)
    #expect(await store.payload() == .search)
}

@Test func noFilesMeansNoKB() async {
    let store = KnowledgeStore(api: FakeUploader(tokens: 0))
    #expect(await store.configure([]).mode == .none)
    #expect(await store.payload() == .none)
}

@Test func uploadFailureFallsBackToPageText() async throws {
    let store = KnowledgeStore(api: FakeUploader(tokens: 100, uploadError: TestError()))
    _ = await store.configure([try KnowledgeFixtures.makeDir()])
    guard case .inline(let blocks) = await store.payload() else { Issue.record(); return }
    #expect(texts(blocks).contains { $0.hasPrefix("### report.pdf\n") && $0.contains("кешування") })
}

@Test func reconfiguringReusesUploadedFile() async throws {
    let api = FakeUploader(tokens: 100)
    let store = KnowledgeStore(api: api)
    let dir = try KnowledgeFixtures.makeDir()
    _ = await store.configure([dir])
    _ = await store.configure([dir])
    #expect(api.uploads == ["report.pdf"])
}

@Test func prewarmSendsZeroTokenRequest() async throws {
    let api = FakeUploader(tokens: 100)
    let store = KnowledgeStore(api: api)
    _ = await store.configure([try KnowledgeFixtures.makeDir()])
    await store.prewarm()
    #expect(api.sent.count == 1)
    #expect(api.sent[0].maxTokens == 0)
}

@Test func tokenCountSendsPDFInlineNotAsFile() async throws {
    let api = FakeUploader(tokens: 100)
    _ = await KnowledgeStore(api: api).configure([try KnowledgeFixtures.makeDir()])
    let blocks = try #require(api.counted.first).messages[0].content
    #expect(!blocks.contains { if case .document = $0 { true } else { false } })
    #expect(blocks.contains { if case .pdf(_, let title) = $0 { title == "report.pdf" } else { false } })
}
