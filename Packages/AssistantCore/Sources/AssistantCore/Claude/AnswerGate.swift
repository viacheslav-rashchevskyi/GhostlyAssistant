import Foundation

public enum GateOutput: Equatable, Sendable {
    case undecided
    case suppressed
    case emit(String)
}

/// Holds back streamed text until it is clear whether the model answered or returned the "no answer" sentinel.
public struct AnswerGate: Sendable {
    private enum State { case waiting, suppressed, open }

    private let sentinel: Character
    private var state = State.waiting
    private var buffer = ""

    public init(sentinel: Character = "∅") {
        self.sentinel = sentinel
    }

    public mutating func feed(_ delta: String) -> GateOutput {
        switch state {
        case .suppressed:
            return .suppressed
        case .open:
            return .emit(delta)
        case .waiting:
            buffer += delta
            guard let first = buffer.first(where: { !$0.isWhitespace }) else { return .undecided }
            if first == sentinel {
                state = .suppressed
                return .suppressed
            }
            state = .open
            let text = String(buffer.drop(while: { $0.isWhitespace }))
            buffer = ""
            return .emit(text)
        }
    }
}
