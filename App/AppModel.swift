import AssistantCore
import Foundation
import os

struct CardAnswer: Identifiable, Equatable {
    let id: UUID
    var question: String
    var text = ""
    var latency: Latency?
    var lookingUpKB = false
    var error: String?
}

enum CardStatus: Equatable {
    case ready
    case needsKey
    case needsPermission
    case downloadingModel(Double)
    case error(String)
}

/// Wires capture, Whisper and the core pipeline together and holds what the card shows.
@MainActor
final class AppModel: ObservableObject {
    static let apiKeyAccount = "anthropic-api-key"
    static let maxAnswers = 20

    @Published private(set) var answers: [CardAnswer] = []
    @Published private(set) var audioPresent = false
    @Published private(set) var status: CardStatus = .ready
    @Published var isCardVisible = true

    private static let log = Logger(subsystem: "local.ghostlyassistant.app", category: "app")
    private let keychain = KeychainStore()
    private let capture = SystemAudioCapture()
    private let whisper = WhisperTranscriber()
    private var pipeline: AssistantPipeline?
    private var eventsTask: Task<Void, Never>?
    private var captureRunning = false

    var hasAPIKey: Bool { !(keychain.read(Self.apiKeyAccount) ?? "").isEmpty }

    func start() async {
        migrateKeyFromOldName()
        guard let key = keychain.read(Self.apiKeyAccount), !key.isEmpty else {
            status = .needsKey
            return
        }
        guard ScreenPermission.granted else {
            ScreenPermission.request()
            status = .needsPermission
            return
        }
        do {
            status = .downloadingModel(0)
            try await whisper.load { [weak self] p in
                Task { @MainActor in
                    guard let self, case .downloadingModel = self.status else { return }
                    self.status = .downloadingModel(p)
                }
            }
            let pipeline = AssistantPipeline(
                transcriber: whisper,
                screenshots: ScreenshotService(),
                claude: ClaudeClient(apiKey: key),
                knowledge: NoKnowledge()
            )
            install(pipeline)
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
        guard let pipeline else { return }
        Task { await pipeline.ask(text) }
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
        case .answerStarted(let id, let question):
            if let i = index(id) {
                answers[i].question = question
            } else {
                answers.append(CardAnswer(id: id, question: question))
            }
        case .answerDelta(let id, let text):
            if let i = index(id) { answers[i].text += text }
        case .kbLookup(let id):
            if let i = index(id) {
                answers[i].lookingUpKB = true
            } else {
                answers.append(CardAnswer(id: id, question: "…", lookingUpKB: true))
            }
        case .answerFinished(let id, let latency):
            if let i = index(id) {
                answers[i].latency = latency
                answers[i].lookingUpKB = false
            }
        case .answerFailed(let id, let message):
            if let i = index(id) {
                answers[i].error = message
                answers[i].lookingUpKB = false
            }
        }
        if answers.count > Self.maxAnswers { answers.removeFirst(answers.count - Self.maxAnswers) }
    }

    /// The app was first built as "ZoomAssistant"; carry a key saved under that name over once.
    private func migrateKeyFromOldName() {
        let old = KeychainStore(service: "local.zoomassistant.app")
        guard !hasAPIKey, let key = old.read(Self.apiKeyAccount) else { return }
        guard (try? keychain.write(key, account: Self.apiKeyAccount)) != nil else { return }
        old.delete(Self.apiKeyAccount)
    }

    private func index(_ id: UUID) -> Int? {
        answers.firstIndex { $0.id == id }
    }
}
