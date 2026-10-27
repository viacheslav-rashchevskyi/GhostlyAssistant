import AppKit
import CoreText
import Foundation

/// Builds a folder with one file of every supported kind plus two that must be skipped.
enum KnowledgeFixtures {
    static func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try pdf(pages: ["Вступ і мета роботи.", "Розділ 3.2 кешування LRU"]).write(to: dir.appendingPathComponent("report.pdf"))
        try docx("Вступ до курсової роботи").write(to: dir.appendingPathComponent("intro.docx"))
        try Data("# Нотатки\nСписок літератури.".utf8).write(to: dir.appendingPathComponent("notes.md"))
        try Data("Простий текст.".utf8).write(to: dir.appendingPathComponent("plain.txt"))
        try png().write(to: dir.appendingPathComponent("pic.png"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.xyz"))
        try Data("not a pdf at all".utf8).write(to: dir.appendingPathComponent("broken.pdf"))
        return dir
    }

    static func makeEmptyDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func pdf(pages: [String]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for text in pages {
            ctx.beginPDFPage(nil)
            let attr = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 72, y: 760)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    static func docx(_ text: String) throws -> Data {
        let attr = NSAttributedString(string: text)
        return try attr.data(from: NSRange(location: 0, length: attr.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }

    static func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
}
