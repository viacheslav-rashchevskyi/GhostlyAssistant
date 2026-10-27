import AppKit
import AssistantCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings in a glass window that, like the chat, is excluded from screen capture.
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
            w.backgroundColor = .clear
            w.excludeFromCapture()
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 420)
            w.isOpaque = false
            // Same system glass and tint as the chat; the titled window clips it to its own rounded corners.
            w.contentView = GlassStyle.make(NSHostingView(rootView: SettingsView(model: model)), cornerRadius: 0)
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
                SpeechCard(model: model)
                WhisperModelCard(model: model)
                KnowledgeCard(model: model)
                ScreenShareCard()
            }
            .padding(.horizontal, 22)
            .padding(.top, 48) // clears the window buttons
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
        .id(model.uiLanguage) // rebuild every string when the interface language changes
        .frame(minWidth: 460, minHeight: 420)
        .environment(\.colorScheme, .dark)
    }
}

private let accent = LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

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
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 18))
    }
}

// MARK: - Interface language

private struct LanguageCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "globe", tint: .green, title: L("Язык интерфейса"), subtitle: L("Язык меню, чата и настроек")) {
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
        SettingsCard(icon: "key.fill", tint: .purple, title: L("Ключ Claude API"),
                     subtitle: L("Хранится только в Связке ключей macOS")) {
            if model.hasAPIKey && !editing {
                HStack {
                    Label(L("Ключ сохранён"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button(L("Заменить")) { withAnimation(.smooth) { editing = true } }
                        .buttonStyle(.glass)
                }
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $key)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                        .onSubmit(save)
                    Button(L("Сохранить"), action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasAPIKey {
                        Button(L("Отмена")) { withAnimation(.smooth) { editing = false; key = "" } }
                            .buttonStyle(.glass)
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
        SettingsCard(icon: "sparkles", tint: .orange, title: L("Модель Claude"),
                     subtitle: L("Кто отвечает на вопросы. Цена — за 1M токенов на вход / выход")) {
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
                        Text(model.price(for: info)?.localizedLabel ?? L("цена неизвестна"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
            }
            HStack(spacing: 8) {
                if model.claudeModelsLoading {
                    ProgressView().controlSize(.small)
                    Text(L("Обновляю список и цены…"))
                } else {
                    Image(systemName: model.claudeModelsFromAPI ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(model.claudeModelsFromAPI ? Color.green : Color.orange)
                    Text(model.claudeModelsFromAPI
                         ? (model.claudePrices.isEmpty ? L("Список из API, цены из встроенной таблицы") : L("Список из API, цены с anthropic.com"))
                         : L("Нет связи с API — показаны известные модели"))
                }
                Spacer()
                Button {
                    Task { await model.refreshClaudeModels() }
                } label: {
                    Label(L("Обновить"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
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
                    .fill(selected ? Color.purple.opacity(0.16) : Color.white.opacity(hovering ? 0.07 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(accent.opacity(0.7)) : AnyShapeStyle(Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
    }
}

/// The model in use: a quiet live dot instead of another chip, since the row is already highlighted.
private struct ActiveStatus: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.8), radius: 3)
                .phaseAnimator([1.0, 0.35]) { dot, opacity in dot.opacity(opacity) } animation: { _ in .easeInOut(duration: 1.1) }
            Text(L("Активна"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// A small glass capsule with an icon, tinted by its kind.
private struct Badge: View {
    enum Kind { case recommended, downloaded }

    let text: String
    let kind: Kind

    private var icon: String {
        switch kind {
        case .recommended: "sparkle"
        case .downloaded: "arrow.down.circle.fill"
        }
    }

    private var colors: [Color] {
        switch kind {
        case .recommended: [Color(red: 0.25, green: 0.85, blue: 0.55), Color(red: 0.2, green: 0.75, blue: 0.85)]
        case .downloaded: [Color(red: 0.35, green: 0.55, blue: 1), Color(red: 0.35, green: 0.55, blue: 1)]
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text.prefix(1).uppercased() + text.dropFirst())
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(kind == .downloaded ? AnyShapeStyle(colors[0]) : AnyShapeStyle(.white))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background {
            if kind == .downloaded {
                Capsule().fill(colors[0].opacity(0.16))
                    .overlay(Capsule().strokeBorder(colors[0].opacity(0.45), lineWidth: 0.75))
            } else {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                    .shadow(color: colors[0].opacity(0.45), radius: 4, y: 1)
            }
        }
        .fixedSize()
    }
}

// MARK: - Whisper model

private struct WhisperModelCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "cpu", tint: .indigo, title: L("Модель распознавания"),
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
                .buttonStyle(.glass)
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
                .buttonStyle(.glass)
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
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            Text(info.sizeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

// MARK: - Speech

private struct SpeechCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(icon: "waveform", tint: .pink, title: L("Распознавание речи"),
                     subtitle: L("Whisper работает на Mac, без интернета")) {
            LanguageRow(icon: "person.wave.2.fill", title: L("Собеседники в звонке"),
                        hint: L("Что слушает Whisper из звука Zoom"), selection: $model.callLanguage)
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

private struct LanguageRow: View {
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
        SettingsCard(icon: "books.vertical.fill", tint: .blue, title: L("База знаний"),
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
                        .buttonStyle(.glass)
                        .disabled(state.isLoading)
                    Button(L("Очистить"), role: .destructive) { model.clearKnowledge() }
                        .buttonStyle(.glass)
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
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? AnyShapeStyle(accent) : AnyShapeStyle(Color.white.opacity(0.2)))
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(targeted ? Color.purple.opacity(0.12) : Color.clear)
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
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovering ? 0.08 : 0.04)))
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
                    Text(L("Целиком в контексте · %@ токенов", state.tokens.formatted()))
                case .search:
                    Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
                    Text(L("Поиск по базе · %@ токенов", state.tokens.formatted()))
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
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .contentTransition(.numericText())
        .animation(.smooth, value: state)
    }
}

// MARK: - Screen sharing

private struct ScreenShareCard: View {
    private let steps = [
        "Zoom → Settings → Share Screen → Advanced",
        "Screen capture mode → «Advanced capture with window filtering»",
        L("Проверьте на устройстве другого участника, что чата не видно")
    ]

    var body: some View {
        SettingsCard(icon: "eye.slash.fill", tint: .teal, title: L("Демонстрация экрана"),
                     subtitle: L("Как спрятать чат от трансляции в Zoom")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.teal.opacity(0.3)))
                        Text(step).font(.callout)
                    }
                }
            }
            Text(L("Если чат всё равно виден — демонстрируйте отдельное окно, а не весь экран, или другой дисплей (чат держите на экране ноутбука)."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(L("Скрыть или показать чат:")).font(.callout)
                ForEach(["⌥", "⌘", "H"], id: \.self) { key in
                    Text(key)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .frame(minWidth: 24, minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.15)))
                }
            }
        }
    }
}
