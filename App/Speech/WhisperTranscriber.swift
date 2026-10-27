import AssistantCore
import Foundation
import WhisperKit

enum TranscriberError: Error {
    case notLoaded
}

/// Local Ukrainian speech recognition with Whisper large-v3-turbo.
actor WhisperTranscriber: SpeechTranscribing {
    static let variant = "large-v3-v20240930_626MB"

    private var kit: WhisperKit?

    static var modelsBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GhostlyAssistant/Models", isDirectory: true)
    }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard kit == nil else { return }
        let folder: URL
        if let local = Self.localModelFolder() {
            folder = local
        } else {
            folder = try await WhisperKit.download(variant: Self.variant, downloadBase: Self.modelsBase) { p in
                progress(p.fractionCompleted)
            }
        }
        progress(1)
        kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        ))
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let kit else { throw TranscriberError.notLoaded }
        let options = DecodingOptions(
            task: .transcribe,
            language: "uk",
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A previously downloaded model folder, so launches work offline.
    private static func localModelFolder() -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: modelsBase, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(variant) {
            let encoder = url.appendingPathComponent("AudioEncoder.mlmodelc")
            if fm.fileExists(atPath: encoder.path) { return url }
        }
        return nil
    }
}
