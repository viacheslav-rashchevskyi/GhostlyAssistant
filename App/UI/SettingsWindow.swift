import AppKit
import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings in their own window that, like the chat, is excluded from screen capture.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = L("Настройки")
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = Theme.windowNS
            w.excludeFromCapture()
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 420)
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsHeader(status: model.status)
                LanguageCard(model: model)
                APIKeyCard(model: model)
                ClaudeModelCard(model: model)
                GenerationCard(model: model)
                AnswerStyleCard(model: model)
                SpeechCard(model: model)
                WhisperModelCard(model: model)
                AppearanceCard(model: model)
                KnowledgeCard(model: model)
                ScreenShareCard()
            }
            .padding(.horizontal, 22)
            .padding(.top, 48) // clears the window buttons
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
        .id(model.uiLanguage) // rebuild every string when the interface language changes
        .tint(Theme.accent)
        .frame(minWidth: 460, minHeight: 420)
    }
}

private let accent = Theme.accent

private struct SettingsHeader: View {
    let status: CardStatus

    private var statusText: (String, Color) {
        switch status {
        case .ready: (L("Работает"), .green)
        case .needsKey: (L("Нужен ключ API"), .orange)
        case .needsPermission: (L("Нужно разрешение на запись экрана"), .orange)
        case .downloadingModel: (L("Загружается модель распознавания"), .blue)
        case .error: (L("Ошибка запуска"), .red)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("GhostlyAssistant")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Circle().fill(statusText.1).frame(width: 7, height: 7)
                    Text(statusText.0).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Card scaffold

private struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
    }
}

// MARK: - Interface language

private struct LanguageCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "globe", title: L("Язык интерфейса"), subtitle: L("Язык меню, чата и настроек")) {
            Picker("", selection: $model.uiLanguage) {
                ForEach(UILanguage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - API key

private struct APIKeyCard: View {
    @ObservedObject var model: AppModel
    @State private var editing = false
    @State private var key = ""

    var body: some View {
        SettingsCard(icon: "key.fill", title: L("Ключ Claude API"),
                     subtitle: L("Хранится только в Связке ключей macOS")) {
            if model.hasAPIKey && !editing {
                HStack {
                    Label(L("Ключ сохранён"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button(L("Заменить")) { withAnimation(.smooth) { editing = true } }
                        .buttonStyle(.quiet)
                }
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $key)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
                        .onSubmit(save)
                    Button(L("Сохранить"), action: save)
                        .buttonStyle(.accent)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasAPIKey {
                        Button(L("Отмена")) { withAnimation(.smooth) { editing = false; key = "" } }
                            .buttonStyle(.quiet)
                    }
                }
                .transition(.blurReplace)
                Link(L("Где взять ключ →"), destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }
        }
    }

    private func save() {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.saveAPIKey(key)
        key = ""
        withAnimation(.smooth) { editing = false }
    }
}

// MARK: - Claude model

private struct ClaudeModelCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "sparkles", title: L("Модель Claude"),
                     subtitle: L("Кто отвечает на вопросы")) {
            CollapsibleList(items: model.claudeModels, isTop: { info in
                ClaudeCatalogFallback.top.contains(info.id) || info.model == model.claudeModel
            }, order: { info in ClaudeCatalogFallback.top.firstIndex(of: info.id) ?? Int.max }) { info in
                    SelectableRow(selected: model.claudeModel == info.model) {
                        withAnimation(.smooth) { model.claudeModel = info.model }
                    } content: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(info.displayName.replacingOccurrences(of: "Claude ", with: "")).font(.body.weight(.medium))
                                if info.model == .haiku { Badge(text: L("рекомендуется"), kind: .recommended) }
                            }
                            Text(ClaudeCatalogFallback.note(for: info.id)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
            }
            HStack(spacing: 8) {
                if model.claudeModelsLoading {
                    ProgressView().controlSize(.small)
                    Text(L("Обновляю список…"))
                } else {
                    Image(systemName: model.claudeModelsFromAPI ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.claudeModelsFromAPI ? Color.green : Color.orange)
                    Text(model.claudeModelsFromAPI
                         ? L("Список из API")
                         : L("Нет связи с API — показаны известные модели"))
                }
                Spacer()
                Button {
                    Task { await model.refreshClaudeModels() }
                } label: {
                    Label(L("Обновить"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.quiet)
                .controlSize(.small)
                .disabled(model.claudeModelsLoading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task { await model.refreshClaudeModels() }
    }
}

/// The best few options up front; the full list unfolds on demand.
private struct CollapsibleList<Item: Identifiable & Equatable, Row: View>: View {
    let items: [Item]
    let isTop: (Item) -> Bool
    let order: (Item) -> Int
    @ViewBuilder let row: (Item) -> Row
    @State private var expanded = false

    private var top: [Item] { items.filter(isTop).sorted { order($0) < order($1) } }
    private var rest: [Item] { items.filter { !isTop($0) } }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(top) { row($0) }
            if expanded {
                ForEach(rest) { row($0) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !rest.isEmpty {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(expanded ? L("Свернуть") : L("Все модели (%d)", items.count))
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .clipped()
    }
}

/// A row that highlights when chosen, with a radio marker on the left.
private struct SelectableRow<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accentSoft : Color.primary.opacity(hovering ? 0.07 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
    }
}

/// The model in use: a quiet green dot instead of another chip, since the row is already highlighted.
/// Static on purpose: an endless animation re-renders the window every frame.
private struct ActiveStatus: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.8), radius: 3)
            Text(L("Активна"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A small flat capsule: the accent for "recommended", a neutral tone step for "downloaded".
private struct Badge: View {
    enum Kind { case recommended, downloaded }

    let text: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind == .recommended ? "sparkle" : "arrow.down.circle.fill")
                .font(.system(size: 8, weight: .bold))
            Text(text.prefix(1).uppercased() + text.dropFirst())
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(kind == .recommended ? Theme.onAccent : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(kind == .recommended ? Theme.accent : Theme.raised))
        .fixedSize()
    }
}

// MARK: - Whisper model

private struct WhisperModelCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "cpu", title: L("Модель распознавания"),
                     subtitle: L("Версия Whisper. Крупнее — точнее, но медленнее")) {
            CollapsibleList(items: WhisperCatalog.models, isTop: { info in
                WhisperCatalog.top.contains(info.variant) || info.variant == model.whisperVariant
            }, order: { info in WhisperCatalog.top.firstIndex(of: info.variant) ?? Int.max }) { info in
                WhisperRow(info: info, model: model)
            }
            if let error = model.whisperError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(L("Скачано моделей: %d · занято на диске %@", model.installedWhisper.count, ByteCountFormatter.string(fromByteCount: model.whisperDiskBytes, countStyle: .file)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.smooth, value: model.whisperDiskBytes)
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.whisperFolder.path(percentEncoded: false))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    try? FileManager.default.createDirectory(at: model.whisperFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.whisperFolder)
                } label: {
                    Label(L("Открыть"), systemImage: "folder.fill")
                }
                .buttonStyle(.quiet)
                .controlSize(.small)
                .help(L("Открыть папку с моделями в Finder"))
            }
        }
        .onAppear { model.refreshInstalledWhisper() }
    }
}

private struct WhisperRow: View {
    let info: WhisperModelInfo
    @ObservedObject var model: AppModel

    private var selected: Bool { model.whisperVariant == info.variant }
    private var installed: Bool { model.installedWhisper.contains(info.variant) }
    private var progress: Double? { model.whisperDownloads[info.variant] }
    private var loading: Bool { model.whisperLoading == info.variant }
    private var deleting: Bool { model.whisperDeleting.contains(info.variant) }

    var body: some View {
        SelectableRow(selected: selected) {
            model.selectWhisper(info.variant)
        } content: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(L(info.title)).font(.body.weight(.medium))
                    if info.variant == WhisperCatalog.recommended { Badge(text: L("рекомендуется"), kind: .recommended) }
                }
                Text(info.note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            status
        }
        .disabled((model.whisperLoading != nil && !loading) || deleting)
        .animation(.smooth, value: deleting)
        .animation(.smooth, value: installed)
    }

    @State private var confirmDelete = false

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            if let progress {
                ProgressView(value: progress).frame(width: 60)
                Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button {
                    model.cancelWhisperDownload(info.variant)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Отменить загрузку"))
            } else if loading {
                ProgressView().controlSize(.small)
                Text(L("загружаю")).font(.caption).foregroundStyle(.secondary)
            } else if deleting {
                ProgressView().controlSize(.small)
                Text(L("удаляю")).font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity)
            } else if installed {
                if selected {
                    ActiveStatus()
                } else {
                    Badge(text: L("скачана"), kind: .downloaded)
                }
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.quiet)
                .controlSize(.small)
                .disabled(selected)
                .help(selected ? L("Модель используется — сначала выберите другую") : L("Удалить с диска"))
                .confirmationDialog(L("Удалить модель «%@»?", L(info.title)), isPresented: $confirmDelete) {
                    Button(L("Удалить (%@)", info.sizeLabel), role: .destructive) { model.deleteWhisper(info.variant) }
                } message: {
                    Text(L("Файлы модели будут удалены с диска. Её всегда можно скачать снова."))
                }
            } else {
                Button {
                    model.downloadWhisper(info.variant)
                } label: {
                    Label(L("Скачать"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.quiet)
                .controlSize(.small)
            }
            Text(info.sizeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

// MARK: - Answer style

// MARK: - Model parameters

/// Thinking, effort and reply length; every row is tagged as changing how fast answers arrive.
private struct GenerationCard: View {
    @ObservedObject var model: AppModel
    @State private var typed = ""

    private var resolved: ResolvedGeneration { model.resolvedGeneration }
    private var range: ClosedRange<Int> { model.maxTokensRange }

    var body: some View {
        SettingsCard(icon: "dial.medium.fill", title: L("Параметры модели"),
                     subtitle: L("Как глубоко модель думает над ответом")) {
            row(title: L("Рассуждения"), hint: L("Адаптивно — модель думает перед ответом, первый текст появляется позже")) {
                Picker("", selection: $model.generation.thinking) {
                    Text(L("Выкл")).tag(GenerationSettings.Thinking.off)
                    Text(L("Адаптивно")).tag(GenerationSettings.Thinking.adaptive)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.claudeModel.alwaysThinks || !model.claudeModel.supportsAdaptiveThinking)
            } notes: { thinkingNotes }

            Divider().opacity(0.3)

            row(title: L("Глубина"), hint: L("High и выше — ответ заметно дольше")) {
                Picker("", selection: $model.generation.effort) {
                    ForEach(GenerationSettings.Effort.allCases, id: \.self) { level in
                        Text(Self.title(level)).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.claudeModel.supportedEfforts.isEmpty)
            } notes: { effortNotes }

            Divider().opacity(0.3)

            row(title: L("Максимальная длина ответа"),
                hint: L("Ограничение сверху: длинные ответы идут дольше, слишком мало — ответ оборвётся")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { model.generation.maxTokens == nil },
                        set: { model.generation.maxTokens = $0 ? nil : resolved.maxTokens }
                    )) {
                        Text(model.generation.maxTokens == nil ? L("Авто — сейчас %d токенов", resolved.maxTokens) : L("Авто"))
                    }
                    .tint(Theme.accent)
                    if let chosen = model.generation.maxTokens {
                        HStack(spacing: 10) {
                            Slider(value: Binding(
                                get: { Self.position(of: chosen, in: range) },
                                set: { model.generation.maxTokens = Self.tokens(at: $0, in: range) }
                            ))
                            .tint(Theme.accent)
                            TextField("", text: $typed)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .frame(width: 70)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))
                                .onSubmit(commitTyped)
                                .onAppear { typed = String(chosen) }
                                .onChange(of: chosen) { _, new in typed = String(new) }
                        }
                        Text(L("От %d до %d токенов — максимум берётся у выбранной модели", range.lowerBound, range.upperBound))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } notes: { lengthNotes }

            HStack {
                Spacer()
                Button(L("Сбросить к быстрым настройкам")) { withAnimation(.smooth) { model.generation = .fast } }
                    .buttonStyle(.quiet)
                    .disabled(model.generation == .fast)
            }
        }
    }

    private func row<Control: View, Notes: View>(title: String, hint: String, @ViewBuilder control: () -> Control,
                                                @ViewBuilder notes: () -> Notes) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title).font(.body.weight(.medium))
                Spacer()
                SpeedTag()
            }
            control()
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            notes()
        }
    }

    @ViewBuilder private var thinkingNotes: some View {
        if resolved.adjustments.contains(.alwaysThinks) {
            note(L("Эта модель всегда рассуждает"))
        } else if resolved.adjustments.contains(.adaptiveUnsupported) || !model.claudeModel.supportsAdaptiveThinking {
            note(L("Эта модель не умеет адаптивные рассуждения"))
        } else if resolved.adjustments.contains(.thinkingTurnedOnForEffort) {
            note(L("На глубине выше High эта модель не отвечает без рассуждений — они включены"))
        }
    }

    @ViewBuilder private var effortNotes: some View {
        if resolved.adjustments.contains(.effortUnsupported) {
            note(L("Эта модель не поддерживает настройку глубины"))
        }
        ForEach(resolved.adjustments.compactMap { if case .effortLowered(let to) = $0 { to } else { nil } }, id: \.self) { to in
            note(L("Эта модель не поддерживает %@ — будет %@", Self.title(model.generation.effort), Self.title(to)))
        }
    }

    @ViewBuilder private var lengthNotes: some View {
        ForEach(resolved.adjustments.compactMap { if case .maxTokensClamped(let to) = $0 { to } else { nil } }, id: \.self) { to in
            note(L("У этой модели максимум %d токенов", to))
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func commitTyped() {
        let digits = typed.filter(\.isNumber)
        guard let value = Int(digits) else { typed = String(model.generation.maxTokens ?? resolved.maxTokens); return }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        model.generation.maxTokens = clamped
        typed = String(clamped)
    }

    private static func title(_ level: GenerationSettings.Effort) -> String {
        switch level {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        }
    }

    /// The slider is logarithmic, so 256…128K is usable end to end.
    private static func position(of tokens: Int, in range: ClosedRange<Int>) -> Double {
        let lo = log(Double(range.lowerBound)), hi = log(Double(range.upperBound))
        guard hi > lo else { return 0 }
        return (log(Double(min(max(tokens, range.lowerBound), range.upperBound))) - lo) / (hi - lo)
    }

    /// Rounded to 256 so the field doesn't show noise like 3517.
    private static func tokens(at position: Double, in range: ClosedRange<Int>) -> Int {
        let lo = log(Double(range.lowerBound)), hi = log(Double(range.upperBound))
        let raw = exp(lo + position * (hi - lo))
        return min(max(Int((raw / 256).rounded()) * 256, range.lowerBound), range.upperBound)
    }
}

/// Marks a setting that changes how fast answers arrive.
private struct SpeedTag: View {
    var body: some View {
        Label(L("Влияет на скорость"), systemImage: "speedometer")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.raised))
    }
}

private struct AnswerStyleCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "text.bubble.fill", title: L("Стиль ответов"),
                     subtitle: L("Насколько подробно и в каком тоне отвечать")) {
            Picker("", selection: Binding(
                get: { model.answerStyle.length },
                set: { model.answerStyle.length = $0 }
            )) {
                Text(L("Коротко")).tag(AnswerStyle.Length.brief)
                Text(L("Обычно")).tag(AnswerStyle.Length.balanced)
                Text(L("Подробно")).tag(AnswerStyle.Length.detailed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(L("Свои инструкции (необязательно)")).font(.caption).foregroundStyle(.secondary)
                TextField(L("Например: отвечай как студент, защищающий курсовую"),
                          text: Binding(get: { model.answerStyle.custom }, set: { model.answerStyle.custom = $0 }),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceCard: View {
    @ObservedObject var model: AppModel

    private let sizes: [(String, Double)] = [("А", 0.9), ("А", 1.0), ("А", 1.15), ("А", 1.3)]

    var body: some View {
        SettingsCard(icon: "slider.horizontal.3", title: L("Вид и запуск"),
                     subtitle: L("Тема, размер текста и автозапуск")) {
            HStack(spacing: 10) {
                Text(L("Тема")).frame(maxWidth: .infinity, alignment: .leading)
                Picker(L("Тема"), selection: $model.theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 10) {
                Text(L("Размер текста")).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(sizes.enumerated()), id: \.offset) { i, item in
                    Button {
                        model.fontScale = item.1
                    } label: {
                        Text(item.0)
                            .font(.system(size: 11 + CGFloat(i) * 3, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(abs(model.fontScale - item.1) < 0.01 ? Theme.accentSoft : Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(abs(model.fontScale - item.1) < 0.01 ? Theme.accent : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle(isOn: $model.launchAtLogin) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Запускать при входе в систему"))
                    Text(L("GhostlyAssistant будет готов сразу после включения Mac")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
        }
    }
}

// MARK: - Speech

private struct SpeechCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "waveform", title: L("Распознавание речи"),
                     subtitle: L("Whisper работает на Mac, без интернета")) {
            LanguageRow(icon: "person.wave.2.fill", title: L("Собеседники в звонке"),
                        hint: L("Что слушает Whisper из звука звонка"), selection: $model.callLanguage)
            Divider().opacity(0.3)
            LanguageRow(icon: "mic.fill", title: L("Ваш голос"),
                        hint: L("Вопросы, которые вы задаёте кнопкой микрофона"), selection: $model.micLanguage)
            Text(L("Точно выбранный язык распознаётся быстрее и надёжнее, чем автоопределение. Ответ всегда приходит на языке вопроса."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LanguageRow: View {
    let icon: String
    let title: String
    let hint: String
    @Binding var selection: SpeechLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(SpeechLanguage.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - Knowledge base

private struct KnowledgeCard: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false

    private var state: KnowledgeState { model.knowledge }

    var body: some View {
        SettingsCard(icon: "books.vertical.fill", title: L("База знаний"),
                     subtitle: L("Необязательно. PDF, Word, текст, Markdown и картинки")) {
            DropZone(targeted: dropTargeted, choose: choose)
                .dropDestination(for: URL.self) { urls, _ in
                    model.addKnowledge(urls)
                    return !urls.isEmpty
                } isTargeted: { dropTargeted = $0 }

            if !state.paths.isEmpty {
                VStack(spacing: 2) {
                    ForEach(state.paths, id: \.self) { url in
                        KnowledgeRow(url: url, skipped: state.skipped.contains(url.lastPathComponent)) {
                            model.removeKnowledge(url)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.smooth, value: state.paths)

                HStack(spacing: 8) {
                    ModeBadge(state: state)
                    Spacer()
                    Button(L("Перечитать")) { Task { await model.reloadKnowledge() } }
                        .buttonStyle(.quiet)
                        .disabled(state.isLoading)
                    Button(L("Очистить"), role: .destructive) { model.clearKnowledge() }
                        .buttonStyle(.quiet)
                }

                let unreadable = state.skipped.filter { name in !state.paths.contains { $0.lastPathComponent == name } }
                if !unreadable.isEmpty {
                    Label(L("Пропущены: %@", unreadable.joined(separator: ", ")), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func choose() {
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

private struct DropZone: View {
    let targeted: Bool
    let choose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 22))
                .foregroundStyle(accent)
                .symbolEffect(.bounce, value: targeted)
            Text(L("Перетащите файлы или папку сюда"))
                .font(.callout)
            Button(L("Выбрать…"), action: choose)
                .buttonStyle(.quiet)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.2)))
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(targeted ? Theme.accentSoft : Color.clear)
        )
        .scaleEffect(targeted ? 1.01 : 1)
        .animation(.spring(duration: 0.3), value: targeted)
    }
}

private struct KnowledgeRow: View {
    let url: URL
    let skipped: Bool
    let remove: () -> Void
    @State private var hovering = false

    private var icon: String {
        if url.hasDirectoryPath { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "docx": return "doc.text.fill"
        case "png", "jpg", "jpeg": return "photo.fill"
        default: return "doc.plaintext.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(skipped ? AnyShapeStyle(Color.orange) : AnyShapeStyle(accent))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent).lineLimit(1)
                Text(url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if skipped {
                Text(L("не читается")).font(.caption2).foregroundStyle(.orange)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help(L("Убрать из базы"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
    }
}

private struct ModeBadge: View {
    let state: KnowledgeState

    var body: some View {
        HStack(spacing: 6) {
            if state.isLoading {
                ProgressView().controlSize(.mini)
                Text(L("Читаю файлы…"))
            } else {
                switch state.mode {
                case .inline:
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    Text(L("Целиком в контексте"))
                case .search:
                    Image(systemName: "magnifyingglass").foregroundStyle(accent)
                    Text(L("Поиск по базе"))
                case .none:
                    Image(systemName: "questionmark.circle")
                    Text(L("Нечего читать"))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .contentTransition(.numericText())
        .animation(.smooth, value: state)
    }
}

// MARK: - Screen sharing

private struct ScreenShareCard: View {
    private let steps = [
        L("В программе созвонов демонстрируйте отдельное окно, а не весь экран"),
        L("Или транслируйте другой дисплей, а чат держите на экране ноутбука"),
        L("Проверьте на устройстве другого участника, что чата не видно")
    ]

    var body: some View {
        SettingsCard(icon: "eye.slash.fill", title: L("Демонстрация экрана"),
                     subtitle: L("Как держать чат вне трансляции в любой программе созвонов")) {
            Text(L("По умолчанию чат скрыт от демонстрации экрана. Если в какой-то программе он всё же виден, выполните эти шаги:"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.accentSoft))
                        Text(step).font(.callout)
                    }
                }
            }
            Text(L("Работает в Zoom, Google Meet, Teams, Discord и других: в трансляцию попадает только выбранное окно или дисплей."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(L("Скрыть или показать чат:")).font(.callout)
                ForEach(["⌥", "⌘", "H"], id: \.self) { key in
                    Text(key)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .frame(minWidth: 24, minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                }
            }
        }
    }
}
