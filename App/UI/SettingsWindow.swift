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
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Настройки"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = .clear
            w.sharingType = .none
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 420)
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate()
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
                APIKeyCard(model: model)
                KnowledgeCard(model: model)
                ScreenShareCard()
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
        .frame(minWidth: 460, minHeight: 420)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .environment(\.colorScheme, .dark)
    }
}

private let accent = LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

private struct SettingsHeader: View {
    let status: CardStatus

    private var statusText: (String, Color) {
        switch status {
        case .ready: ("Работает", .green)
        case .needsKey: ("Нужен ключ API", .orange)
        case .needsPermission: ("Нужно разрешение на запись экрана", .orange)
        case .downloadingModel: ("Загружается модель распознавания", .blue)
        case .error: ("Ошибка запуска", .red)
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

// MARK: - API key

private struct APIKeyCard: View {
    @ObservedObject var model: AppModel
    @State private var editing = false
    @State private var key = ""

    var body: some View {
        SettingsCard(icon: "key.fill", tint: .purple, title: "Ключ Claude API",
                     subtitle: "Хранится только в Связке ключей macOS") {
            if model.hasAPIKey && !editing {
                HStack {
                    Label("Ключ сохранён", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Заменить") { withAnimation(.smooth) { editing = true } }
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
                    Button("Сохранить", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if model.hasAPIKey {
                        Button("Отмена") { withAnimation(.smooth) { editing = false; key = "" } }
                            .buttonStyle(.glass)
                    }
                }
                .transition(.blurReplace)
                Link("Где взять ключ →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
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

// MARK: - Knowledge base

private struct KnowledgeCard: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false

    private var state: KnowledgeState { model.knowledge }

    var body: some View {
        SettingsCard(icon: "books.vertical.fill", tint: .blue, title: "База знаний",
                     subtitle: "Необязательно. PDF, Word, текст, Markdown и картинки") {
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
                    Button("Перечитать") { Task { await model.reloadKnowledge() } }
                        .buttonStyle(.glass)
                        .disabled(state.isLoading)
                    Button("Очистить", role: .destructive) { model.clearKnowledge() }
                        .buttonStyle(.glass)
                }

                let unreadable = state.skipped.filter { name in !state.paths.contains { $0.lastPathComponent == name } }
                if !unreadable.isEmpty {
                    Label("Пропущены: \(unreadable.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
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
        panel.prompt = "Добавить"
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
            Text("Перетащите файлы или папку сюда")
                .font(.callout)
            Button("Выбрать…", action: choose)
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
                Text("не читается").font(.caption2).foregroundStyle(.orange)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help("Убрать из базы")
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
                Text("Читаю файлы…")
            } else {
                switch state.mode {
                case .inline:
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                    Text("Целиком в контексте · \(state.tokens.formatted()) токенов")
                case .search:
                    Image(systemName: "magnifyingglass").foregroundStyle(.cyan)
                    Text("Поиск по базе · \(state.tokens.formatted()) токенов")
                case .none:
                    Image(systemName: "questionmark.circle")
                    Text("Нечего читать")
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
        "Проверьте на устройстве другого участника, что чата не видно"
    ]

    var body: some View {
        SettingsCard(icon: "eye.slash.fill", tint: .teal, title: "Демонстрация экрана",
                     subtitle: "Как спрятать чат от трансляции в Zoom") {
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
            Text("Если чат всё равно виден — демонстрируйте отдельное окно, а не весь экран, или другой дисплей (чат держите на экране ноутбука).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Скрыть или показать чат:").font(.callout)
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
