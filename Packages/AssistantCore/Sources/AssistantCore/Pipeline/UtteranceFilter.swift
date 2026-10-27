import Foundation

/// Cheap local check that keeps filler and known Whisper hallucinations away from Claude.
public enum UtteranceFilter {
    static let minWords = 3
    /// Phrases Whisper invents on silence or music (Ukrainian, Russian, English); matched as word stems.
    static let hallucinations = [
        "дякую за перегляд", "продовження далі", "субтитр",
        "продолжение следует", "спасибо за просмотр",
        "thank you for watching", "thanks for watching"
    ]

    public static func shouldSend(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(.whitespaces).inverted)
            .joined(separator: " ")
        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count >= minWords else { return false }
        let joined = words.joined(separator: " ")
        return !hallucinations.contains { joined.contains($0) }
    }
}
