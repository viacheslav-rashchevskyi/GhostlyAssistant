import AppKit
import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

/// The first-run guide: a fixed-size window that, like the chat, is excluded from screen capture.
/// The chat stays hidden while it is open and appears when the guide closes.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    private let onboarding: Onboarding
    private let showChat: () -> Void

    init(model: AppModel, onboarding: Onboarding, showChat: @escaping () -> Void) {
        self.model = model
        self.onboarding = onboarding
        self.showChat = showChat
    }

    var isOpen: Bool { window?.isVisible == true }

    func windowWillClose(_ notification: Notification) {
        showChat()
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = L("Мастер настройки")
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = Theme.windowNS
            w.excludeFromCapture()
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, onboarding: onboarding, showChat: showChat) { [weak self] in
                self?.onboarding.finish()
                self?.window?.close()
            })
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var onboarding: Onboarding
    let showChat: () -> Void
    let done: () -> Void

    @State private var permissionGranted = false

    var body: some View {
        HStack(spacing: 0) {
            StepList(onboarding: onboarding, isComplete: isComplete)
                .frame(width: 220)
                .background(Theme.raised)
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.top, 44)
                        .padding(.bottom, 20)
                }
                .scrollIndicators(.never)
                Divider().opacity(0.4)
                footer
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 780, height: 580)
        .tint(Theme.accent)
        .id(model.uiLanguage) // rebuild every string when the interface language changes
        .task { await watchPermission() }
        .onAppear {
            // The speech model is the slowest part of setup, so it starts downloading right away.
            if !model.installedWhisper.contains(model.whisperVariant) { model.downloadWhisper(model.whisperVariant) }
        }
    }

    @ViewBuilder private var content: some View {
        switch onboarding.step {
        case .welcome: WelcomeStep(model: model)
        case .key: KeyStep(model: model)
        case .permission: PermissionStep(granted: permissionGranted)
        case .languages: LanguagesStep(model: model)
        case .speech: SpeechStep(model: model)
        case .usage: UsageStep(model: model, onboarding: onboarding, showChat: showChat)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if onboarding.step != .welcome {
                Button(L("Назад")) { withAnimation(.smooth) { onboarding.back() } }
                    .buttonStyle(.quiet)
            }
            Spacer()
            if onboarding.step == .key && !model.apiKeySaved {
                Button(L("Пропустить")) {
                    onboarding.keySkipped = true
                    withAnimation(.smooth) { onboarding.next() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if onboarding.step == .usage {
                Button(L("Готово"), action: done)
                    .buttonStyle(.accent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Дальше")) { withAnimation(.smooth) { onboarding.next() } }
                    .buttonStyle(.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete(onboarding.step))
            }
        }
    }

    private func isComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .languages, .usage: true
        case .key: model.apiKeySaved
        case .permission: permissionGranted
        case .speech: model.installedWhisper.contains(model.whisperVariant)
        }
    }

    /// The system doesn't notify when access is granted, so the guide looks every couple of seconds.
    private func watchPermission() async {
        while !Task.isCancelled {
            let granted = await ScreenPermission.check()
            if granted != permissionGranted { permissionGranted = granted }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

// MARK: - Step list

private struct StepList: View {
    @ObservedObject var onboarding: Onboarding
    let isComplete: (OnboardingStep) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GhostlyAssistant")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            ForEach(OnboardingStep.allCases) { step in
                Button {
                    withAnimation(.smooth) { onboarding.step = step }
                } label: {
                    row(step)
                }
                .buttonStyle(.plain)
                .disabled(!onboarding.canOpen(step))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 52)
    }

    private func row(_ step: OnboardingStep) -> some View {
        let current = step == onboarding.step
        let skipped = step == .key && onboarding.keySkipped && !isComplete(.key)
        let done = !current && isComplete(step) && step.rawValue < onboarding.furthest.rawValue
        return HStack(spacing: 10) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if current {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2)
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                }
            }
            .font(.system(size: 16))
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Theme.accent : (onboarding.canOpen(step) ? Color.primary : Color.secondary))
                if skipped {
                    Text(L("пропущено")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(current ? Theme.accentSoft : Color.clear))
        .contentShape(Rectangle())
    }
}

// MARK: - Shared pieces

private struct StepHeader: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 22)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StatusLine: View {
    enum Kind { case ok, warning, error, progress }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .progress: ProgressView().controlSize(.small)
            }
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .padding(.bottom, 12)
            StepHeader(title: L("Добро пожаловать в GhostlyAssistant"),
                       text: L("Помощник слушает звонок, замечает вопросы и подсказывает ответы в небольшом окне рядом. Настройка займёт пару минут."))
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "waveform", title: L("Речь распознаётся на вашем Mac"),
                           text: L("Звук звонка не уходит в облако — только текст вопроса."))
                FeatureRow(icon: "text.bubble.fill", title: L("Ответы появляются сразу"),
                           text: L("Текст идёт потоком, пока модель отвечает."))
                FeatureRow(icon: "eye.slash.fill", title: L("Окно скрыто от демонстрации экрана"),
                           text: L("Собеседники видят ваш экран, но не чат с подсказками."))
            }
            .padding(.bottom, 24)
            Panel {
                HStack {
                    Text(L("Язык интерфейса"))
                    Spacer()
                    Picker("", selection: $model.uiLanguage) {
                        ForEach(UILanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                HStack {
                    Text(L("Тема"))
                    Spacer()
                    Picker("", selection: $model.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
    }
}

// MARK: - 2. API key

private struct KeyStep: View {
    @ObservedObject var model: AppModel
    @State private var key = ""
    @State private var checking = false
    @State private var result: AppModel.KeyCheck?
    @State private var replacing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: L("Ключ Claude API"),
                       text: L("Ответы строит Claude. Ключ хранится только в Связке ключей macOS и никуда, кроме Anthropic, не отправляется."))
            Panel {
                if model.apiKeySaved && !replacing {
                    HStack {
                        StatusLine(kind: .ok, text: resultText ?? L("Ключ сохранён"))
                        Spacer()
                        Button(L("Заменить")) { replacing = true; result = nil }
                            .buttonStyle(.quiet)
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("sk-ant-…", text: $key)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.raised))
                            .onSubmit(check)
                        Button(L("Проверить"), action: check)
                            .buttonStyle(.accent)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    }
                    if checking {
                        StatusLine(kind: .progress, text: L("Проверяю ключ…"))
                    } else if result == .invalid {
                        StatusLine(kind: .error, text: L("Ключ не подходит. Проверьте, что он скопирован целиком."))
                    }
                }
            }
            Text(L("Можно пропустить и добавить ключ позже в настройках — без него приложение распознаёт речь, но не отвечает."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultText: String? {
        switch result {
        case .valid(let n): L("Ключ подходит — доступно моделей: %d", n)
        case .unverified: L("Ключ сохранён. Нет связи с API — проверим при следующем запуске.")
        default: nil
        }
    }

    private func check() {
        let candidate = key
        checking = true
        result = nil
        Task {
            let r = await model.checkAndSaveAPIKey(candidate)
            checking = false
            result = r
            if r != .invalid { key = ""; replacing = false }
        }
    }
}

// MARK: - 3. Permission

private struct PermissionStep: View {
    let granted: Bool
    @State private var openedSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: L("Запись экрана и звука"),
                       text: L("Это разрешение даёт приложению звук звонка и снимок экрана в момент вопроса — чтобы ответ учитывал слайд или код, о котором спрашивают."))
            Panel {
                if granted {
                    StatusLine(kind: .ok, text: L("Разрешение выдано"))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("1. Откройте настройки и включите GhostlyAssistant в списке «Запись экрана и системного звука»."))
                        Text(L("2. macOS применит разрешение только после перезапуска — нажмите «Перезапустить», мастер продолжит с этого шага."))
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(L("Открыть настройки")) {
                            ScreenPermission.request()
                            ScreenPermission.openSettings()
                            openedSettings = true
                        }
                        .buttonStyle(.accent)
                        Button(L("Перезапустить")) { Onboarding.relaunch() }
                            .buttonStyle(.quiet)
                            .disabled(!openedSettings)
                    }
                    StatusLine(kind: .progress, text: L("Жду разрешение…"))
                }
            }
        }
    }
}

// MARK: - 4. Languages

private struct LanguagesStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: L("Языки"),
                       text: L("Точно выбранный язык распознаётся быстрее и надёжнее, чем автоопределение. Ответ всегда приходит на языке вопроса."))
            Panel {
                LanguageRow(icon: "person.wave.2.fill", title: L("Собеседники в звонке"),
                            hint: L("Что слушает Whisper из звука звонка"), selection: $model.callLanguage)
                Divider().opacity(0.3)
                LanguageRow(icon: "mic.fill", title: L("Ваш голос"),
                            hint: L("Вопросы, которые вы задаёте кнопкой микрофона"), selection: $model.micLanguage)
            }
        }
    }
}

// MARK: - 5. Speech model

private struct SpeechStep: View {
    @ObservedObject var model: AppModel

    private var current: WhisperModelInfo? { WhisperCatalog.models.first { $0.variant == model.whisperVariant } }
    private var progress: Double? { model.whisperDownloads[model.whisperLoading ?? model.whisperVariant] }

    /// "Large v3 Turbo, сжатая — 627 МБ · Быстро и точно", with the recommended one marked.
    private func menuTitle(_ info: WhisperModelInfo) -> String {
        let base = "\(info.title) — \(info.sizeLabel) · \(info.note)"
        return info.variant == WhisperCatalog.recommended ? base + " · " + L("рекомендуется") : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: L("Модель распознавания речи"),
                       text: L("Whisper работает на вашем Mac, без интернета. Модель скачивается один раз."))
            Panel {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current?.title ?? model.whisperVariant).font(.body.weight(.medium))
                        Text([current?.note, current?.sizeLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu(L("Другая модель")) {
                        ForEach(WhisperCatalog.models) { info in
                            Button(menuTitle(info)) { model.selectWhisper(info.variant) }
                                .disabled(info.variant == model.whisperVariant)
                        }
                    }
                    .fixedSize()
                    .disabled(model.whisperLoading != nil)
                }
                if model.installedWhisper.contains(model.whisperVariant) && model.whisperLoading == nil {
                    StatusLine(kind: .ok, text: L("Модель готова"))
                } else if let progress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress).tint(Theme.accent)
                        Text(L("Скачиваю… %d%%", Int(progress * 100))).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    StatusLine(kind: .progress, text: L("Готовлю загрузку…"))
                }
                if let error = model.whisperError {
                    StatusLine(kind: .error, text: error)
                    Button(L("Повторить")) { model.downloadWhisper(model.whisperVariant) }.buttonStyle(.quiet)
                }
            }
        }
    }
}

// MARK: - 6. Usage

private struct UsageStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var onboarding: Onboarding
    let showChat: () -> Void
    @State private var asked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: L("Всё готово к звонку"),
                       text: L("Запустите звонок как обычно — помощник сам услышит вопрос и ответит в чате."))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 16) {
                FeatureRow(icon: "bubble.left.and.bubble.right.fill", title: L("Чат в углу экрана"),
                           text: L("Его можно двигать и растягивать; на демонстрации экрана его не видно."))
                FeatureRow(icon: "keyboard", title: L("⌥⌘H — скрыть или показать чат"),
                           text: L("Работает из любого приложения."))
                FeatureRow(icon: "arrowshape.turn.up.left.fill", title: L("⌥⌘A — ответить на пропущенную реплику"),
                           text: L("Если помощник решил, что это был не вопрос."))
                FeatureRow(icon: "mic.fill", title: L("Кнопка микрофона — спросить самому"),
                           text: L("Нажмите, скажите вопрос, нажмите ещё раз."))
            }
            .padding(.bottom, 20)
            Panel {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("База знаний — необязательно")).font(.body.weight(.medium))
                        Text(model.knowledge.paths.isEmpty
                             ? L("PDF, Word, текст или картинки — например, ваш доклад")
                             : L("Добавлено файлов: %d", model.knowledge.paths.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Добавить файлы…"), action: chooseFiles).buttonStyle(.quiet)
                }
                Divider().opacity(0.3)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Проверить ответы")).font(.body.weight(.medium))
                        Text(testHint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(L("Задать тестовый вопрос")) {
                        showChat()
                        model.ask(L("Чем процесс отличается от потока?"))
                        asked = true
                    }
                    .buttonStyle(.quiet)
                    .disabled(model.status != .ready)
                }
                if !model.apiKeySaved {
                    Button(L("Добавить ключ →")) { withAnimation(.smooth) { onboarding.step = .key } }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .font(.callout)
                }
            }
        }
    }

    private var testHint: String {
        if !model.apiKeySaved { return L("Добавьте ключ, чтобы проверить ответы") }
        if model.status != .ready { return L("Станет доступно, когда приложение запустится") }
        return asked ? L("Ответ появится в чате") : L("Один небольшой запрос к API — ответ появится в чате")
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .plainText, .png, .jpeg, .folder,
                                     UTType(filenameExtension: "md") ?? .plainText,
                                     UTType(filenameExtension: "docx") ?? .data]
        panel.prompt = L("Добавить")
        if panel.runModal() == .OK { model.addKnowledge(panel.urls) }
    }
}
