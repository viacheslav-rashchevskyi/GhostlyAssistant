import Foundation

/// Rolling transcript of the call plus the last few answered questions.
public struct TranscriptBuffer: Sendable {
    private let window: TimeInterval
    private let historyLimit: Int
    private var lines: [(text: String, at: Date)] = []
    public private(set) var history: [QAPair] = []

    public init(window: TimeInterval = 180, historyLimit: Int = 3) {
        self.window = window
        self.historyLimit = historyLimit
    }

    public mutating func append(_ text: String, at: Date) {
        lines.append((text, at))
        lines.removeAll { at.timeIntervalSince($0.at) > window }
    }

    public func recent(now: Date) -> [String] {
        lines.filter { now.timeIntervalSince($0.at) <= window }.map(\.text)
    }

    public mutating func addAnswer(_ qa: QAPair) {
        history.append(qa)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }
}
