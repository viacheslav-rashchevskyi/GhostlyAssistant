import Foundation

public enum Resampler {
    /// Downmixes interleaved audio to mono and linearly resamples it to 16 kHz.
    public static func toMono16k(_ interleaved: [Float], sampleRate: Double, channels: Int) -> [Float] {
        let mono: [Float]
        if channels <= 1 {
            mono = interleaved
        } else {
            let frames = interleaved.count / channels
            mono = (0..<frames).map { f in
                var sum: Float = 0
                for c in 0..<channels { sum += interleaved[f * channels + c] }
                return sum / Float(channels)
            }
        }
        guard sampleRate != 16_000, !mono.isEmpty else { return mono }
        let ratio = sampleRate / 16_000
        let outCount = Int(Double(mono.count) / ratio)
        return (0..<outCount).map { i in
            let pos = Double(i) * ratio
            let i0 = Int(pos)
            let i1 = min(i0 + 1, mono.count - 1)
            let t = Float(pos - Double(i0))
            return mono[i0] * (1 - t) + mono[i1] * t
        }
    }
}
