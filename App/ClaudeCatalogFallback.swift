import AssistantCore
import Foundation

/// Shown until (or if) the Models API answers: the current generally available models.
enum ClaudeCatalogFallback {
    static let models: [ClaudeModelInfo] = [
        ("claude-fable-5-1", "Claude Fable 5.1"),
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
        ("claude-opus-5", "Claude Opus 5"),
        ("claude-sonnet-5", "Claude Sonnet 5"),
        ("claude-opus-4-8", "Claude Opus 4.8"),
        ("claude-sonnet-4-6", "Claude Sonnet 4.6"),
        ("claude-haiku-4-5", "Claude Haiku 4.5")
    ].map { ClaudeModelInfo(id: $0.0, displayName: $0.1, createdAt: nil) }

    /// A short Russian note on what the model is good for in a live call.
    static func note(for id: String) -> String {
        if id.contains("fable") || id.contains("mythos") { return "Самая мощная — долго думает, для звонка медленная" }
        if id.contains("opus") { return "Умная, отвечает медленнее" }
        if id.contains("sonnet") { return "Баланс ума и скорости" }
        if id.contains("haiku") { return "Самая быстрая — для живого звонка" }
        return "Модель Claude"
    }
}
