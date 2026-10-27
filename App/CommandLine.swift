import AssistantCore
import AVFoundation
import Foundation

/// `GhostlyAssistant --transcribe <audio file>`: prints the Whisper transcript and timing, then exits.
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
            try await whisper.load(variant: UserDefaults.standard.string(forKey: "whisperModel") ?? WhisperCatalog.recommended) { p in
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

/// `GhostlyAssistant --ask "<utterance>"`: runs one utterance through the real pipeline (saved key and knowledge base) and prints the events.
extension DebugCommandLine {
    static var askText: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--ask"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    struct FixedTranscript: SpeechTranscribing {
        let text: String
        func transcribe(_ samples: [Float]) async throws -> String { text }
    }

    static func runAsk(_ text: String) async -> Never {
        guard let key = KeychainStore().read(AppModel.apiKeyAccount) else {
            print("error: no API key saved")
            exit(1)
        }
        let client = ClaudeClient(apiKey: key)
        let store = KnowledgeStore(api: client)
        let paths = (UserDefaults.standard.stringArray(forKey: "knowledgePaths") ?? []).map { URL(fileURLWithPath: $0) }
        let kb = await store.configure(paths)
        print("knowledge: \(kb.mode) \(kb.tokens) tokens, skipped \(kb.skipped)")
        let model = UserDefaults.standard.string(forKey: "claudeModel").flatMap(ClaudeModel.init(rawValue:)) ?? .haiku
        print("model: \(model.rawValue)")
        await store.setModel(model)
        let pipeline = AssistantPipeline(transcriber: FixedTranscript(text: text), screenshots: ScreenshotService(), claude: client, knowledge: store)
        await pipeline.setModel(model)
        let printer = Task {
            for await event in pipeline.events {
                switch event {
                case .answerDelta(_, let t): print(t, terminator: "")
                case .answerFinished(_, let latency): print("\n[finished \(latency.label)]"); exit(0)
                case .answerFailed(_, let message): print("\n[failed] \(message)"); exit(1)
                case .activity(_, .skipped(let reason)): print("[skipped \(reason)]"); exit(0)
                default: print("[\(event)]")
                }
            }
        }
        await pipeline.handle(Utterance(samples: [0], endedAt: Date()))
        _ = await printer.value
        exit(0)
    }
}
