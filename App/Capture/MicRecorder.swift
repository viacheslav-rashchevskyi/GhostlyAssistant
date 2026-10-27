import AssistantCore
import AVFoundation

/// Push-to-talk microphone recording for the user's own spoken questions, as 16 kHz mono samples.
final class MicRecorder: @unchecked Sendable {
    /// 0…1 loudness of the latest buffer, for the recording animation.
    var onLevel: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start() throws {
        lock.withLock { samples = [] }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channels = Int(format.channelCount)
            let mono = (0..<frames).map { i in (0..<channels).reduce(Float(0)) { $0 + data[$1][i] } / Float(channels) }
            let chunk = Resampler.toMono16k(mono, sampleRate: format.sampleRate, channels: 1)
            self.lock.withLock { self.samples += chunk }
            let rms = (mono.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(mono.count, 1))).squareRoot()
            self.onLevel?(min(1, rms * 12))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }
}
