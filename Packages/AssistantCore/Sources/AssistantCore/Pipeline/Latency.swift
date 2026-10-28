import Foundation

public struct Latency: Equatable, Sendable {
    public let timeToFirstToken: TimeInterval

    public init(timeToFirstToken: TimeInterval) {
        self.timeToFirstToken = timeToFirstToken
    }

    /// For example "0,8 с".
    public var label: String {
        let seconds = (timeToFirstToken * 10).rounded() / 10
        return String(format: "%.1f", seconds).replacingOccurrences(of: ".", with: ",") + " с"
    }
}

public enum RussianPlural {
    public static func previousAnswers(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let noun: String
        if mod10 == 1 && mod100 != 11 {
            noun = "предыдущий ответ"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            noun = "предыдущих ответа"
        } else {
            noun = "предыдущих ответов"
        }
        return "↑ ещё \(n) \(noun)"
    }
}
