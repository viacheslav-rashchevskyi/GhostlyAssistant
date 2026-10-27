import AppKit
import Foundation
import PDFKit

/// Tools Claude uses to read a knowledge base too large to send whole.
public enum KBTools {
    static let pageImageSize = NSSize(width: 1200, height: 1200)

    public static let definitions: [ToolDefinition] = [
        ToolDefinition(
            name: "search_kb",
            description: "Search the user's reference materials. Returns snippets with document title and page.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["query": .object(["type": .string("string"), "description": .string("Keywords to search for")])]),
                "required": .array([.string("query")])
            ])
        ),
        ToolDefinition(
            name: "open_page",
            description: "Open one page of a reference document to read it fully; PDF pages include an image of the page.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document": .object(["type": .string("string"), "description": .string("Document title as returned by search_kb")]),
                    "page": .object(["type": .string("integer"), "description": .string("1-based page number")])
                ]),
                "required": .array([.string("document"), .string("page")])
            ])
        )
    ]

    public static func run(name: String, input: JSONValue, index: BM25Index, documents: [KBDocument]) -> [ContentBlock] {
        guard case .object(let args) = input else { return [.text("Invalid input.")] }
        switch name {
        case "search_kb":
            guard case .string(let query)? = args["query"] else { return [.text("Missing query.")] }
            let hits = index.search(query)
            guard !hits.isEmpty else { return [.text("No matches in the knowledge base.")] }
            return [.text(hits.map { "[\($0.title), p. \($0.page)]\n\($0.snippet)" }.joined(separator: "\n\n"))]
        case "open_page":
            guard case .string(let title)? = args["document"] else { return [.text("Missing document.")] }
            guard let doc = documents.first(where: { $0.title == title }) else { return [.text("Document not found: \(title)")] }
            let page: Int = if case .number(let n)? = args["page"] { Int(n) } else { 1 }
            return open(doc, page: page)
        default:
            return [.text("Unknown tool: \(name)")]
        }
    }

    private static func open(_ doc: KBDocument, page: Int) -> [ContentBlock] {
        if doc.kind == .image {
            guard let data = try? Data(contentsOf: doc.url) else { return [.text("Cannot read \(doc.title).")] }
            return [.text("[\(doc.title)]"), doc.url.pathExtension.lowercased() == "png" ? .imagePNG(data) : .imageJPEG(data)]
        }
        guard (1...max(doc.pages.count, 1)).contains(page), page <= doc.pages.count else {
            return [.text("\(doc.title) has \(doc.pages.count) page(s).")]
        }
        var blocks: [ContentBlock] = [.text("[\(doc.title), p. \(page)]\n\(doc.pages[page - 1])")]
        if doc.kind == .pdf, let png = renderPDFPage(doc.url, index: page - 1) {
            blocks.append(.imagePNG(png))
        }
        return blocks
    }

    private static func renderPDFPage(_ url: URL, index: Int) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: index) else { return nil }
        let image = page.thumbnail(of: pageImageSize, for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
