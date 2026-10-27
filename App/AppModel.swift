import AssistantCore
import Foundation
import os

/// One exchange in the chat: something heard on the call (or asked by the user) and the assistant's reply.
struct ChatTurn: Identifiable, Equatable {
    enum Source: Equatable { case call, user }
    enum Step: Equatable { case transcribing, thinking, searching, answering, done, skipped(SkipReason) }

    let id: UUID
    var source: Source
    var step: Step
    var question: String?
    var answer = ""
    var latency: Latency?
    var error: String?

    var isSkipped: Bool {
        if case .skipped = step { true } else { false }
    }
}

enum CardStatus: Equatable {
    case ready
    case needsKey
    case needsPermission
    case downloadingModel(Double)
    case error(String)
}

/// What the settings show about the knowledge base.
struct KnowledgeState: Equatable {
    var paths: [URL] = []
    var mode: KBMode = .none
    var tokens = 0
    var skipped: [String] = []
    var isLoading = false
}

enum MicState: Equatable {
    case idle
    case recording
    case transcribing
}

/// Wires capture, Whisper and the core pipeline together and holds what the chat shows.
@MainActor
final class AppModel: ObservableObject {
    nonisolated static let apiKeyAccount = "anthropic-api-key"
    static let maxTurns = 40

    @Published private(set) var turns: [ChatTurn] = []
    @Published private(set) var audioPresent = false
    @Published private(set) var status: CardStatus = .ready
    @Published private(set) var mic: MicState = .idle
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var micError: String?
    @Published var isCardVisible = true
    @Published private(set) var knowledge = KnowledgeState()
    @Published var callLanguage: SpeechLanguage = AppModel.storedLanguage("callLanguage", default: .uk) {
        didSet {
            UserDefaults.standard.set(callLanguage.rawValue, forKey: "callLanguage")
            Task { await whisper.setCallLanguage(callLanguage.code) }
        }
    }
    @Published var claudeModel: ClaudeModel = UserDefaults.standard.string(forKey: "claudeModel").flatMap(ClaudeModel.init(rawValue:)) ?? .haiku {
        didSet {
            UserDefaults.standard.set(claudeModel.rawValue, forKey: "claudeModel")
            let model = claudeModel
            Task {
                await pipeline?.setModel(model)
                await knowledgeStore?.setModel(model)
                await knowledgeStore?.prewarm()
            }
        }
    }
    @Published private(set) var whisperVariant = UserDefaults.standard.string(forKey: "whisperModel") ?? WhisperCatalog.recommended
    @Published private(set) var installedWhisper: Set<String> = []
    @Published private(set) var whisperDownloads: [String: Double] = [:]
    @Published private(set) var whisperLoading: String?
    @Published private(set) var whisperError: String?
    @Published private(set) var whisperDiskBytes: Int64 = 0
    @Published var micLanguage: SpeechLanguage = AppModel.storedLanguage("micLanguage", default: .ru) {
        didSet { UserDefaults.standard.set(micLanguage.rawValue, forKey: "micLanguage") }
    }

    private static let log = Logger(subsystem: "local.ghostlyassistant.app", category: "app")
    private let keychain = KeychainStore()
    private let capture = SystemAudioCapture()
    private let whisper = WhisperTranscriber()
    private let recorder = MicRecorder()
    private var pipeline: AssistantPipeline?
    private var eventsTask: Task<Void, Never>?
    private var captureRunning = false
    private var knowledgeStore: KnowledgeStore?
    private static let knowledgePathsKey = "knowledgePaths"


    var hasAPIKey: Bool { !(keychain.read(Self.apiKeyAccount) ?? "").isEmpty }
    var latestLatency: Latency? { turns.last { $0.latency != nil }?.latency }

    func start() async {
        migrateKeyFromOldName()
        guard let key = keychain.read(Self.apiKeyAccount), !key.isEmpty else {
            status = .needsKey
            return
        }
        guard await ScreenPermission.check() else {
            ScreenPermission.request()
            status = .needsPermission
            return
        }
        do {
            status = .downloadingModel(0)
            await whisper.setCallLanguage(callLanguage.code)
            refreshInstalledWhisper()
            try await whisper.load(variant: whisperVariant) { [weak self] p in
                Task { @MainActor in
                    guard let self, case .downloadingModel = self.status else { return }
                    self.status = .downloadingModel(p)
                }
            }
            refreshInstalledWhisper()
            let client = ClaudeClient(apiKey: key)
            let store = KnowledgeStore(api: client)
            await store.setModel(claudeModel)
            knowledgeStore = store
            let pipeline = AssistantPipeline(
                transcriber: whisper,
                screenshots: ScreenshotService(),
                claude: client,
                knowledge: store
            )
            await pipeline.setModel(claudeModel)
            install(pipeline)
            Task { await reloadKnowledge() }
            if !captureRunning {
                capture.onLevel = { [weak self] present in
                    Task { @MainActor in self?.audioPresent = present }
                }
                try await capture.start()
                captureRunning = true
            }
            status = .ready
        } catch {
            Self.log.error("start failed: \(error.localizedDescription, privacy: .public)")
            status = .error("Не удалось запустить: \(error.localizedDescription)")
        }
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? keychain.write(trimmed, account: Self.apiKeyAccount)
        Task { await start() }
    }

    func ask(_ text: String) {
        guard let pipeline, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await pipeline.ask(text) }
    }

    // MARK: Whisper models

    var whisperFolder: URL { WhisperTranscriber.modelsBase }

    func refreshInstalledWhisper() {
        installedWhisper = Set(WhisperCatalog.models.map(\.variant).filter { WhisperTranscriber.installedFolder($0) != nil })
        whisperDiskBytes = WhisperTranscriber.diskUsage()
    }

    func downloadWhisper(_ variant: String) {
        guard whisperDownloads[variant] == nil else { return }
        whisperError = nil
        whisperDownloads[variant] = 0
        Task {
            do {
                _ = try await WhisperTranscriber.download(variant) { [weak self] p in
                    Task { @MainActor in
                        if self?.whisperDownloads[variant] != nil { self?.whisperDownloads[variant] = p }
                    }
                }
            } catch {
                whisperError = "Не удалось скачать модель: \(error.localizedDescription)"
            }
            whisperDownloads[variant] = nil
            refreshInstalledWhisper()
        }
    }

    /// Switches recognition to `variant`, downloading it first when needed.
    func selectWhisper(_ variant: String) {
        guard variant != whisperVariant, whisperLoading == nil else { return }
        whisperError = nil
        whisperLoading = variant
        if !installedWhisper.contains(variant) { whisperDownloads[variant] = 0 }
        Task {
            do {
                try await whisper.load(variant: variant) { [weak self] p in
                    Task { @MainActor in
                        if self?.whisperDownloads[variant] != nil { self?.whisperDownloads[variant] = p }
                    }
                }
                whisperVariant = variant
                UserDefaults.standard.set(variant, forKey: "whisperModel")
            } catch {
                whisperError = "Не удалось загрузить модель: \(error.localizedDescription)"
            }
            whisperDownloads[variant] = nil
            whisperLoading = nil
            refreshInstalledWhisper()
        }
    }

    /// The model in use can't be deleted; the user picks another one first.
    func deleteWhisper(_ variant: String) {
        guard variant != whisperVariant else { return }
        do {
            try WhisperTranscriber.delete(variant)
        } catch {
            whisperError = "Не удалось удалить модель: \(error.localizedDescription)"
        }
        refreshInstalledWhisper()
    }

    // MARK: Knowledge base

    func addKnowledge(_ urls: [URL]) {
        let merged = savedKnowledgePaths() + urls.filter { !savedKnowledgePaths().contains($0) }
        saveKnowledgePaths(merged)
        Task { await reloadKnowledge() }
    }

    func removeKnowledge(_ url: URL) {
        saveKnowledgePaths(savedKnowledgePaths().filter { $0 != url })
        Task { await reloadKnowledge() }
    }

    func clearKnowledge() {
        saveKnowledgePaths([])
        Task { await reloadKnowledge() }
    }

    /// Re-reads the chosen files, picks inline or search mode, and warms the prompt cache.
    func reloadKnowledge() async {
        let paths = savedKnowledgePaths()
        knowledge.paths = paths
        guard let store = knowledgeStore else { return }
        knowledge.isLoading = true
        let result = await store.configure(paths)
        knowledge = KnowledgeState(paths: paths, mode: result.mode, tokens: result.tokens, skipped: result.skipped)
        await store.prewarm()
    }

    private static func storedLanguage(_ key: String, default fallback: SpeechLanguage) -> SpeechLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(SpeechLanguage.init(rawValue:)) ?? fallback
    }

    private func savedKnowledgePaths() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: Self.knowledgePathsKey) ?? []).map { URL(fileURLWithPath: $0) }
    }

    private func saveKnowledgePaths(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map(\.path), forKey: Self.knowledgePathsKey)
        knowledge.paths = urls
    }

    func clearChat() {
        turns.removeAll()
    }

    /// Push-to-talk: the first call starts recording, the second transcribes it in the user's language and asks it.
    func toggleMic() {
        switch mic {
        case .idle:
            Task { await startRecording() }
        case .recording:
            let samples = recorder.stop()
            mic = .transcribing
            micLevel = 0
            Task {
                let text = (try? await whisper.transcribe(samples, language: micLanguage.code)) ?? ""
                mic = .idle
                if text.isEmpty {
                    micError = "Не расслышал, попробуйте ещё раз"
                } else {
                    ask(text)
                }
            }
        case .transcribing:
            break
        }
    }

    private func startRecording() async {
        micError = nil
        guard await MicRecorder.requestAccess() else {
            micError = "Нет доступа к микрофону — разрешите в Системных настройках"
            return
        }
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.micLevel = level }
        }
        do {
            try recorder.start()
            mic = .recording
        } catch {
            micError = "Микрофон недоступен: \(error.localizedDescription)"
        }
    }

    private func install(_ pipeline: AssistantPipeline) {
        self.pipeline = pipeline
        capture.onUtterance = { u in
            Task { await pipeline.handle(u) }
        }
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            for await event in pipeline.events {
                self?.apply(event)
            }
        }
    }

    private func apply(_ event: CardEvent) {
        switch event {
        case .activity(let id, .transcribing):
            turns.append(ChatTurn(id: id, source: .call, step: .transcribing))
        case .activity(let id, .asked(let text)):
            turns.append(ChatTurn(id: id, source: .user, step: .thinking, question: text))
        case .activity(let id, .heard(let text)):
            update(id) { $0.question = text }
        case .activity(let id, .thinking):
            update(id) { $0.step = .thinking }
        case .activity(let id, .skipped(let reason)):
            update(id) { $0.step = .skipped(reason) }
        case .answerStarted(let id, let question):
            update(id) {
                $0.step = .answering
                if $0.question == nil { $0.question = question }
            }
        case .answerDelta(let id, let text):
            update(id) { $0.answer += text }
        case .kbLookup(let id):
            update(id) { $0.step = .searching }
        case .answerFinished(let id, let latency):
            update(id) {
                $0.step = .done
                $0.latency = latency
            }
        case .answerFailed(let id, let message):
            update(id) {
                $0.step = .done
                $0.error = message
            }
        }
        pruneSkipped()
        if turns.count > Self.maxTurns { turns.removeFirst(turns.count - Self.maxTurns) }
    }

    private func update(_ id: UUID, _ change: (inout ChatTurn) -> Void) {
        guard let i = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[i])
    }

    /// Skipped chatter stays visible only while it is among the newest few turns.
    private func pruneSkipped() {
        let keepFrom = max(0, turns.count - 3)
        turns = turns.enumerated().filter { $0.offset >= keepFrom || !$0.element.isSkipped }.map(\.element)
    }

    /// The app was first built as "ZoomAssistant"; carry a key saved under that name over once.
    private func migrateKeyFromOldName() {
        let old = KeychainStore(service: "local.zoomassistant.app")
        guard !hasAPIKey, let key = old.read(Self.apiKeyAccount) else { return }
        guard (try? keychain.write(key, account: Self.apiKeyAccount)) != nil else { return }
        old.delete(Self.apiKeyAccount)
    }
}
