import AssistantCore
import Foundation
import WhisperKit

enum TranscriberError: Error {
    case notLoaded
}

/// Local speech recognition with a downloadable Whisper model (see `WhisperCatalog`).
actor WhisperTranscriber: SpeechTranscribing {
    static let repoPrefix = "openai_whisper-"

    private var kit: WhisperKit?
    private(set) var loadedVariant: String?
    /// Language of the call audio; nil lets Whisper detect it.
    private var callLanguage: String? = "uk"

    static var modelsBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GhostlyAssistant/Models", isDirectory: true)
    }

    /// Loads `variant`, downloading it first if needed; a no-op when it is already loaded.
    func load(variant: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard loadedVariant != variant || kit == nil else { return }
        let folder: URL
        if let local = Self.installedFolder(variant) {
            folder = local
        } else {
            folder = try await Self.download(variant, progress: progress)
        }
        progress(1)
        kit = nil
        loadedVariant = nil
        kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        ))
        loadedVariant = variant
    }

    func setCallLanguage(_ code: String?) {
        callLanguage = code
    }

    /// Call audio, in the language chosen in settings.
    func transcribe(_ samples: [Float]) async throws -> String {
        try await transcribe(samples, language: callLanguage)
    }

    /// `language` is a Whisper code such as "uk" or "ru"; nil detects the language from the audio.
    func transcribe(_ samples: [Float], language: String?) async throws -> String {
        guard let kit else { throw TranscriberError.notLoaded }
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Model files

    static func download(_ variant: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await WhisperKit.download(variant: variant, downloadBase: modelsBase) { p in
            progress(p.fractionCompleted)
        }
    }

    /// The folder of a fully downloaded model, so launches work offline.
    static func installedFolder(_ variant: String) -> URL? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: modelsBase, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker where url.lastPathComponent == repoPrefix + variant {
            if fm.fileExists(atPath: url.appendingPathComponent("AudioEncoder.mlmodelc").path) { return url }
        }
        return nil
    }

    /// Bytes taken by all downloaded models.
    static func diskUsage() -> Int64 {
        guard let walker = FileManager.default.enumerator(at: modelsBase, includingPropertiesForKeys: [.fileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize) ?? 0)
        }
        return total
    }

    static func delete(_ variant: String) throws {
        if let folder = installedFolder(variant) { try FileManager.default.removeItem(at: folder) }
    }
}
