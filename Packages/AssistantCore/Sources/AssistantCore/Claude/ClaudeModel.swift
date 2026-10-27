import Foundation

/// The Claude models the user can pick, with the request settings each one needs for a fast reply.
public enum ClaudeModel: String, CaseIterable, Sendable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"

    /// Haiku turns thinking off with `disabled`; Sonnet 5.5 rejects that and uses `between_tools`;
    /// Opus 5.5 can't turn it off at all, so thinking is omitted and kept short by low effort.
    var thinking: MessagesRequest.Thinking? {
        switch self {
        case .haiku: MessagesRequest.Thinking(type: "disabled")
        case .sonnet: MessagesRequest.Thinking(type: "between_tools")
        case .opus: nil
        }
    }

    /// Sonnet and Opus can decline on safety classifiers; the server-side fallback retries on another model.
    var fallbacks: String? {
        self == .haiku ? nil : "default"
    }

    static let fallbackBeta = "server-side-fallback-2026-07-01"
}
