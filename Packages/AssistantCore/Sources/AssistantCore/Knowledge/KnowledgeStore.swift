import Foundation
import os

public protocol KBUploading: Sendable {
    func uploadFile(_ data: Data, filename: String, mimeType: String) async throws -> String
    func countTokens(_ r: CountTokensRequest) async throws -> Int
    func send(_ r: MessagesRequest) async throws
}

extension ClaudeClient: KBUploading {}

public enum KBMode: Equatable, Sendable {
    case none, inline, search
}

/// The user's optional reference materials: sent whole when small, searched through tools when large.
public actor KnowledgeStore: KnowledgeProviding {
    private static let log = Logger(subsystem: "local.ghostlyassistant.app", category: "knowledge")
    private let api: KBUploading
    private let threshold: Int
    private var mode = KBMode.none
    private var blocks: [ContentBlock] = []
    private var documents: [KBDocument] = []
    private var index = BM25Index(documents: [])
    private var model = ClaudeModel.haiku
    private var style = AnswerStyle()
    private var generation = GenerationSettings.fast
    /// file_id per PDF, keyed by path and modification date, so re-reading doesn't re-upload.
    private var uploaded: [String: String] = [:]

    public init(api: KBUploading, threshold: Int = 80_000) {
        self.api = api
        self.threshold = threshold
    }

    /// Prompt caches are per model, so the prewarm must use the model that will answer.
    public func setModel(_ model: ClaudeModel) {
        self.model = model
    }

    public func setStyle(_ style: AnswerStyle) {
        self.style = style
    }

    /// Thinking and effort are part of the cached request, so the prewarm must send the same ones.
    public func setGeneration(_ generation: GenerationSettings) {
        self.generation = generation
    }

    public func configure(_ urls: [URL]) async -> (mode: KBMode, tokens: Int, skipped: [String]) {
        let result = KnowledgeLoader.load(urls)
        let skipped = result.skipped.map(\.url.lastPathComponent)
        documents = result.documents
        guard !documents.isEmpty else {
            mode = .none
            blocks = []
            return (.none, 0, skipped)
        }
        blocks = await inlineBlocks(documents)
        let tokens: Int
        do {
            tokens = try await api.countTokens(RequestBuilder.countTokens(kb: countableBlocks(), model: model))
        } catch {
            Self.log.error("count_tokens failed: \(String(describing: error), privacy: .public)")
            tokens = Int.max
        }
        mode = tokens > threshold ? .search : .inline
        index = mode == .search ? BM25Index(documents: documents) : BM25Index(documents: [])
        return (mode, tokens == Int.max ? 0 : tokens, skipped)
    }

    public func prewarm() async {
        guard mode != .none else { return }
        try? await api.send(RequestBuilder.prewarm(kb: payload(), tools: tools(), model: model, style: style, generation: generation))
    }

    public func payload() -> KBPayload {
        switch mode {
        case .none: .none
        case .inline: .inline(blocks)
        case .search: .search
        }
    }

    public func tools() -> [ToolDefinition] {
        mode == .search ? KBTools.definitions : []
    }

    public func execute(tool: String, input: JSONValue) async -> [ContentBlock] {
        guard mode == .search else { return [.text("Knowledge base is already in context.")] }
        return KBTools.run(name: tool, input: input, index: index, documents: documents)
    }

    /// The token counting endpoint rejects Files API references, so PDFs are counted inline.
    private func countableBlocks() -> [ContentBlock] {
        blocks.map { block in
            guard case .document(_, let title, _) = block,
                  let doc = documents.first(where: { $0.title == title && $0.kind == .pdf }),
                  let data = try? Data(contentsOf: doc.url) else { return block }
            return .pdf(data, title: title)
        }
    }

    /// Images first and documents last, so the block carrying the cache marker is text or a document.
    private func inlineBlocks(_ docs: [KBDocument]) async -> [ContentBlock] {
        var images: [ContentBlock] = []
        var texts: [ContentBlock] = []
        var pdfs: [ContentBlock] = []
        for doc in docs {
            switch doc.kind {
            case .image:
                guard let data = try? Data(contentsOf: doc.url) else { continue }
                images.append(doc.url.pathExtension.lowercased() == "png" ? .imagePNG(data) : .imageJPEG(data))
            case .text, .docx:
                texts.append(.text("### \(doc.title)\n\(doc.pages.joined(separator: "\n"))"))
            case .pdf:
                if let id = await upload(doc) {
                    pdfs.append(.document(fileId: id, title: doc.title))
                } else {
                    let pages = doc.pages.enumerated().map { "[p. \($0.offset + 1)]\n\($0.element)" }
                    texts.append(.text("### \(doc.title)\n\(pages.joined(separator: "\n"))"))
                }
            }
        }
        return images + texts + pdfs
    }

    private func upload(_ doc: KBDocument) async -> String? {
        let modified = (try? doc.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(doc.url.path)#\(modified)"
        if let id = uploaded[key] { return id }
        guard let data = try? Data(contentsOf: doc.url),
              let id = try? await api.uploadFile(data, filename: doc.title, mimeType: "application/pdf") else { return nil }
        uploaded[key] = id
        return id
    }
}
