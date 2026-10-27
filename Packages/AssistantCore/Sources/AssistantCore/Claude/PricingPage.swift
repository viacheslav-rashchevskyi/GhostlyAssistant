import Foundation

/// Current per-model prices from Anthropic's public pricing page (the Models API doesn't return prices).
public enum PricingPage {
    static let url = URL(string: "https://platform.claude.com/docs/en/about-claude/pricing.md")!

    public static func fetch(transport: HTTPTransport = URLSessionTransport()) async throws -> [String: ClaudePrice] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw ClaudeError.http(status: response.statusCode, message: "pricing page") }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Reads the first table whose header has "Base input": model display name → base input / output price.
    /// Rows that repeat a model (tiered prices) keep the first, lowest tier.
    public static func parse(_ markdown: String) -> [String: ClaudePrice] {
        var prices: [String: ClaudePrice] = [:]
        var inTable = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inTable {
                inTable = line.hasPrefix("|") && line.contains("Model") && line.contains("Base input")
                continue
            }
            guard line.hasPrefix("|") else { break }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 3, !cells[0].hasPrefix("-"),
                  let input = dollars(cells[1]), let output = dollars(cells[cells.count - 1]) else { continue }
            let name = modelName(cells[0])
            if prices[name] == nil { prices[name] = ClaudePrice(input: input, output: output) }
        }
        return prices
    }

    /// "Claude Mythos 5.1 ([limited availability](…))" → "Claude Mythos 5.1".
    private static func modelName(_ cell: String) -> String {
        let name = cell.range(of: " (").map { String(cell[..<$0.lowerBound]) } ?? cell
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// "$0.10 / MTok<sup>3</sup>" → 0.10.
    private static func dollars(_ cell: String) -> Double? {
        guard let match = cell.firstMatch(of: /\$([0-9]+(?:\.[0-9]+)?)/) else { return nil }
        return Double(match.1)
    }
}
