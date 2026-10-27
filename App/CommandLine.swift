import AssistantCore
import AVFoundation
import Foundation

/// `ZoomAssistant --transcribe <audio file>`: prints the Whisper transcript and timing, then exits.
enum DebugCommandLine {
    static var transcribePath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--transcribe"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func runTranscribe(_ path: String) async -> Never {
        do {
            let samples = try loadSamples(URL(fileURLWithPath: path))
            let whisper = WhisperTranscriber()
            let loadStart = Date()
            try await whisper.load { p in
                FileHandle.standardError.write(Data("download \(Int(p * 100))%\r".utf8))
            }
            print("model loaded in \(String(format: "%.1f", Date().timeIntervalSince(loadStart))) s")
            let start = Date()
            let text = try await whisper.transcribe(samples)
            print("text: \(text)")
            print("transcribed \(String(format: "%.1f", Double(samples.count) / 16_000)) s of audio in \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }

    private static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        let mono = (0..<frames).map { i in (0..<channels).reduce(Float(0)) { $0 + data[$1][i] } / Float(channels) }
        return Resampler.toMono16k(mono, sampleRate: format.sampleRate, channels: 1)
    }
}
