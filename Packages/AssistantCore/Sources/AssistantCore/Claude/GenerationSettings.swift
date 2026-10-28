import Foundation

/// How hard the model works on a reply, chosen in settings. The defaults are the fastest settings for a live call.
public struct GenerationSettings: Equatable, Sendable, Codable {
    public enum Thinking: String, Equatable, Sendable, Codable, CaseIterable {
        case off, adaptive
    }

    public enum Effort: String, Equatable, Sendable, Codable, CaseIterable, Comparable {
        case low, medium, high, xhigh, max

        public static func < (a: Effort, b: Effort) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    public var thinking: Thinking
    public var effort: Effort
    /// Reply length cap in tokens; nil picks one that fits the model and whether it thinks.
    public var maxTokens: Int?

    public init(thinking: Thinking = .off, effort: Effort = .low, maxTokens: Int? = nil) {
        self.thinking = thinking
        self.effort = effort
        self.maxTokens = maxTokens
    }

    public static let fast = GenerationSettings()
    /// Below this a reply almost always stops mid-sentence.
    public static let minMaxTokens = 256
}

/// What a model will actually be sent for some settings, and why it differs from what was chosen.
public struct ResolvedGeneration: Equatable, Sendable {
    public enum Adjustment: Equatable, Sendable {
        /// The model thinks whatever is chosen (Fable, Mythos, Opus 5.5).
        case alwaysThinks
        /// The model only turns thinking off at high effort or below.
        case thinkingTurnedOnForEffort
        /// The model has no adaptive thinking (Haiku 4.5 and older).
        case adaptiveUnsupported
        /// The model takes no effort setting.
        case effortUnsupported
        case effortLowered(to: GenerationSettings.Effort)
        case maxTokensClamped(to: Int)
    }

    public var thinking: MessagesRequest.Thinking?
    public var effort: String?
    public var maxTokens: Int
    public var adjustments: [Adjustment]
}

extension ClaudeModel {
    /// Adjusts the chosen settings to what this model accepts; `maxOutput` is the model's cap from the Models API.
    public func resolve(_ s: GenerationSettings, maxOutput: Int? = nil) -> ResolvedGeneration {
        var adjustments: [ResolvedGeneration.Adjustment] = []

        let levels = supportedEfforts
        var effort: GenerationSettings.Effort?
        if levels.isEmpty {
            adjustments.append(.effortUnsupported)
        } else if levels.contains(s.effort) {
            effort = s.effort
        } else {
            let lowered = levels.last { $0 < s.effort } ?? levels[0]
            effort = lowered
            adjustments.append(.effortLowered(to: lowered))
        }

        var thinking: MessagesRequest.Thinking?
        var thinks = false
        if alwaysThinks {
            thinking = s.thinking == .adaptive ? MessagesRequest.Thinking(type: "adaptive") : nil
            thinks = true
            adjustments.append(.alwaysThinks)
        } else if s.thinking == .adaptive {
            if supportsAdaptiveThinking {
                thinking = MessagesRequest.Thinking(type: "adaptive")
                thinks = true
            } else {
                thinking = offThinking
                adjustments.append(.adaptiveUnsupported)
            }
        } else if let cap = offEffortCap, let effort, effort > cap {
            thinking = MessagesRequest.Thinking(type: "adaptive")
            thinks = true
            adjustments.append(.thinkingTurnedOnForEffort)
        } else {
            thinking = offThinking
        }

        var maxTokens = thinks ? 8192 : 2048
        if let chosen = s.maxTokens {
            let upper = maxOutput ?? maxOutputFallback
            maxTokens = min(max(chosen, GenerationSettings.minMaxTokens), upper)
            if chosen > upper { adjustments.append(.maxTokensClamped(to: upper)) }
        }

        return ResolvedGeneration(thinking: thinking, effort: effort?.rawValue, maxTokens: maxTokens, adjustments: adjustments)
    }

    /// Output cap to use when the Models API didn't report one.
    public var maxOutputFallback: Int {
        Self.effortModels.contains(id) ? 64_000 : 8192
    }

    /// Effort levels the model accepts, lowest first; empty when it takes no effort setting.
    public var supportedEfforts: [GenerationSettings.Effort] {
        guard Self.effortModels.contains(id) else { return [] }
        return Self.noXHigh.contains(id) ? [.low, .medium, .high, .max] : GenerationSettings.Effort.allCases
    }

    public var alwaysThinks: Bool { Self.alwaysThinking.contains(id) }

    /// Every model that takes effort also takes adaptive thinking.
    public var supportsAdaptiveThinking: Bool { Self.effortModels.contains(id) }

    /// Highest effort at which the model still accepts thinking turned off.
    var offEffortCap: GenerationSettings.Effort? {
        Self.offCappedAtHigh.contains(id) ? .high : nil
    }

    private static let noXHigh: Set<String> = ["claude-opus-4-6", "claude-sonnet-4-6"]
    private static let offCappedAtHigh: Set<String> = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5"]
}
