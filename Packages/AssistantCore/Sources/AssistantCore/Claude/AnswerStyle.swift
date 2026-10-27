import Foundation

/// How the user wants answers shaped; added to the system prompt as an operator instruction.
public struct AnswerStyle: Equatable, Sendable {
    public enum Length: String, Sendable, CaseIterable { case brief, balanced, detailed }

    public var length: Length
    public var custom: String

    public init(length: Length = .balanced, custom: String = "") {
        self.length = length
        self.custom = custom
    }

    /// The extra system text, or nil when the style asks for nothing beyond the default prompt.
    var instruction: String? {
        var lines: [String] = []
        switch length {
        case .brief: lines.append("Keep answers to one or two short sentences; give detail only if explicitly asked.")
        case .balanced: break
        case .detailed: lines.append("Give a fuller answer: a short structured explanation with the key reasons, still without preamble.")
        }
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { lines.append(trimmed) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
