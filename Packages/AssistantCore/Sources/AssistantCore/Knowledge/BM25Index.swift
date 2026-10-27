import Foundation

public struct KBHit: Equatable, Sendable {
    public let title: String
    /// 1-based.
    public let page: Int
    public let snippet: String
    public let score: Double
}

/// Keyword search over page chunks of the knowledge base.
public struct BM25Index: Sendable {
    private struct Chunk: Sendable {
        let title: String
        let page: Int
        let text: String
        let terms: [String: Int]
        let length: Int
    }

    static let k1 = 1.2
    static let b = 0.75

    private let chunks: [Chunk]
    private let documentFrequency: [String: Int]
    private let averageLength: Double

    public init(documents: [KBDocument], chunkSize: Int = 800) {
        var chunks: [Chunk] = []
        for doc in documents {
            for (i, page) in doc.pages.enumerated() {
                for text in Self.split(page, maxLength: chunkSize) {
                    let tokens = Self.tokenize(text)
                    guard !tokens.isEmpty else { continue }
                    chunks.append(Chunk(title: doc.title, page: i + 1, text: text,
                                        terms: tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 },
                                        length: tokens.count))
                }
            }
        }
        self.chunks = chunks
        documentFrequency = chunks.reduce(into: [:]) { df, chunk in
            for term in chunk.terms.keys { df[term, default: 0] += 1 }
        }
        averageLength = chunks.isEmpty ? 1 : Double(chunks.map(\.length).reduce(0, +)) / Double(chunks.count)
    }

    public func search(_ query: String, limit: Int = 5) -> [KBHit] {
        let terms = Set(Self.tokenize(query))
        let n = Double(chunks.count)
        let hits = chunks.compactMap { chunk -> KBHit? in
            var score = 0.0
            for term in terms {
                guard let tf = chunk.terms[term], let df = documentFrequency[term] else { continue }
                let idf = log((n - Double(df) + 0.5) / (Double(df) + 0.5) + 1)
                let norm = Double(tf) * (Self.k1 + 1) / (Double(tf) + Self.k1 * (1 - Self.b + Self.b * Double(chunk.length) / averageLength))
                score += idf * norm
            }
            return score > 0 ? KBHit(title: chunk.title, page: chunk.page, snippet: chunk.text, score: score) : nil
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// Splits on whitespace into pieces no longer than `maxLength` characters.
    static func split(_ text: String, maxLength: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !current.isEmpty && current.count + 1 + word.count > maxLength {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word.prefix(maxLength)) : " " + word
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
