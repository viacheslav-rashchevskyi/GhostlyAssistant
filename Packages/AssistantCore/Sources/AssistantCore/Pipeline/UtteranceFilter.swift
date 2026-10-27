import Foundation

/// Cheap local check that keeps filler and known Whisper hallucinations away from Claude.
public enum UtteranceFilter {
    static let minWords = 3
    static let hallucinations = ["дякую за перегляд", "субтитри", "thank you for watching", "продовження далі"]

    public static func shouldSend(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(.whitespaces).inverted)
            .joined()
        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count >= minWords else { return false }
        let joined = words.joined(separator: " ")
        return !hallucinations.contains { joined.contains($0) }
    }
}
