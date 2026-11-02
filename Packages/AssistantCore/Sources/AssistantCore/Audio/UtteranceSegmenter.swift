import Foundation

public struct Utterance: Sendable, Equatable {
    public let samples: [Float]
    public let endedAt: Date

    public init(samples: [Float], endedAt: Date) {
        self.samples = samples
        self.endedAt = endedAt
    }
}

/// Splits a continuous 16 kHz mono stream into utterances using frame RMS and trailing silence.
public final class UtteranceSegmenter {
    private let frameSize: Int
    private let frameDuration: TimeInterval
    private let speechThreshold: Float
    private var minSilenceFrames: Int
    private let minSpeechFrames: Int
    private let maxSamples: Int

    private var pending: [Float] = []
    private var current: [Float] = []
    private var inUtterance = false
    private var speechFrames = 0
    private var trailingSilenceFrames = 0

    public init(
        sampleRate: Double = 16_000,
        frameDuration: TimeInterval = 0.02,
        speechThreshold: Float = 0.01,
        minSilence: TimeInterval = 0.7,
        minSpeech: TimeInterval = 0.3,
        maxUtterance: TimeInterval = 15
    ) {
        frameSize = Int(sampleRate * frameDuration)
        self.frameDuration = frameDuration
        self.speechThreshold = speechThreshold
        minSilenceFrames = Int((minSilence / frameDuration).rounded(.up))
        minSpeechFrames = Int((minSpeech / frameDuration).rounded(.up))
        maxSamples = Int(sampleRate * maxUtterance)
    }

    /// Trailing silence that ends an utterance; longer keeps a speaker's hesitations in one phrase.
    public func setMinSilence(_ seconds: TimeInterval) {
        minSilenceFrames = Int((seconds / frameDuration).rounded(.up))
    }

    public func append(_ samples: [Float], at time: Date) -> [Utterance] {
        pending += samples
        var out: [Utterance] = []
        var offset = 0
        while pending.count - offset >= frameSize {
            let frame = pending[offset..<offset + frameSize]
            offset += frameSize
            if let u = process(frame, at: time) { out.append(u) }
        }
        pending.removeFirst(offset)
        return out
    }

    private func process(_ frame: ArraySlice<Float>, at time: Date) -> Utterance? {
        let isSpeech = Self.rms(frame) > speechThreshold
        guard inUtterance else {
            if isSpeech {
                inUtterance = true
                current = Array(frame)
                speechFrames = 1
                trailingSilenceFrames = 0
            }
            return nil
        }
        current += frame
        if isSpeech {
            speechFrames += 1
            trailingSilenceFrames = 0
        } else {
            trailingSilenceFrames += 1
        }
        if trailingSilenceFrames >= minSilenceFrames {
            let speechPart = Array(current.dropLast(trailingSilenceFrames * frameSize))
            let enough = speechFrames >= minSpeechFrames
            reset()
            return enough ? Utterance(samples: speechPart, endedAt: time) : nil
        }
        if current.count >= maxSamples {
            let cut = Array(current.prefix(maxSamples))
            let enough = speechFrames >= minSpeechFrames
            current = Array(current.dropFirst(maxSamples))
            speechFrames = 0
            trailingSilenceFrames = 0
            return enough ? Utterance(samples: cut, endedAt: time) : nil
        }
        return nil
    }

    private func reset() {
        inUtterance = false
        current = []
        speechFrames = 0
        trailingSilenceFrames = 0
    }

    static func rms(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return 0 }
        let sum = frame.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(frame.count)).squareRoot()
    }
}
