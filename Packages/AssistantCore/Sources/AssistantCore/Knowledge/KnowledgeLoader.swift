import AppKit
import Foundation
import PDFKit

public struct KBDocument: Equatable, Sendable {
    public enum Kind: Sendable, Hashable { case pdf, docx, text, image }

    public let url: URL
    public let kind: Kind
    public let title: String
    /// Page texts for PDFs; a single entry for other documents (empty for images).
    public let pages: [String]
}

public struct SkippedFile: Equatable, Sendable {
    public let url: URL
    public let reason: String
}

public struct LoadResult: Sendable {
    public let documents: [KBDocument]
    public let skipped: [SkippedFile]
}

public enum KnowledgeLoader {
    static let kinds: [String: KBDocument.Kind] = [
        "pdf": .pdf, "docx": .docx, "txt": .text, "md": .text, "png": .image, "jpg": .image, "jpeg": .image
    ]

    /// Reads chosen files and folders (recursively). Unreadable or unsupported files are skipped, never fatal.
    public static func load(_ urls: [URL]) -> LoadResult {
        var documents: [KBDocument] = []
        var skipped: [SkippedFile] = []
        for file in expand(urls) {
            guard let kind = kinds[file.pathExtension.lowercased()] else {
                skipped.append(SkippedFile(url: file, reason: "формат не поддерживается"))
                continue
            }
            if let doc = read(file, kind: kind) {
                documents.append(doc)
            } else {
                skipped.append(SkippedFile(url: file, reason: "не удалось открыть"))
            }
        }
        return LoadResult(documents: documents, skipped: skipped)
    }

    private static func expand(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                files.append(url)
                continue
            }
            let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let item = walker?.nextObject() as? URL {
                if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(item) }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func read(_ url: URL, kind: KBDocument.Kind) -> KBDocument? {
        let title = url.lastPathComponent
        switch kind {
        case .pdf:
            guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else { return nil }
            let pages = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
            return KBDocument(url: url, kind: .pdf, title: title, pages: pages)
        case .docx:
            guard let attr = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) else { return nil }
            return KBDocument(url: url, kind: .docx, title: title, pages: [attr.string])
        case .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return KBDocument(url: url, kind: .text, title: title, pages: [text])
        case .image:
            guard NSImage(contentsOf: url) != nil else { return nil }
            return KBDocument(url: url, kind: .image, title: title, pages: [])
        }
    }
}
