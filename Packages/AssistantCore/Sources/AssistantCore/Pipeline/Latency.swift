import Foundation

public struct Latency: Equatable, Sendable {
    public let timeToFirstToken: TimeInterval
    public let tokensPerSecond: Double?

    public init(timeToFirstToken: TimeInterval, tokensPerSecond: Double?) {
        self.timeToFirstToken = timeToFirstToken
        self.tokensPerSecond = tokensPerSecond
    }

    /// For example "0,8 с · 140 ток/с".
    public var label: String {
        let seconds = (timeToFirstToken * 10).rounded() / 10
        let ttft = String(format: "%.1f", seconds).replacingOccurrences(of: ".", with: ",") + " с"
        guard let tps = tokensPerSecond else { return ttft }
        return "\(ttft) · \(Int(tps.rounded())) ток/с"
    }
}

public enum UkrainianPlural {
    public static func previousAnswers(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let noun: String
        if mod10 == 1 && mod100 != 11 {
            noun = "попередня відповідь"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            noun = "попередні відповіді"
        } else {
            noun = "попередніх відповідей"
        }
        return "↑ ще \(n) \(noun)"
    }
}
