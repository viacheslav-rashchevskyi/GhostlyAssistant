import AppKit
import Sparkle
import SwiftUI

/// The update window: like the other windows, excluded from screen capture.
/// A non-activating panel, so a scheduled check can show it mid-call without taking keyboard focus from the meeting app.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let session: UpdateSession
    private let onUserClose: () -> Void

    init(session: UpdateSession, onUserClose: @escaping () -> Void) {
        self.session = session
        self.onUserClose = onUserClose
    }

    func show(activate: Bool) {
        if window == nil {
            let w = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            w.title = L("Обновление")
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = Theme.windowNS
            w.hidesOnDeactivate = false
            w.becomesKeyOnlyIfNeeded = true
            w.excludeFromCapture()
            w.isReleasedWhenClosed = false
            w.delegate = self
            let host = NSHostingView(rootView: UpdateView(session: session))
            host.sizingOptions = [.preferredContentSize] // the window follows the height of each step
            w.contentView = host
            w.center()
            window = w
        }
        if activate { NSApp.activate() }
        window?.orderFrontRegardless()
        if activate { window?.makeKey() }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onUserClose()
    }
}

// MARK: - Content

struct UpdateView: View {
    @ObservedObject var session: UpdateSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch session.phase {
            case .checking(let cancel):
                header(L("Проверяю обновления…"))
                ProgressView().progressViewStyle(.linear)
                buttons { Button(L("Отмена"), action: cancel).buttonStyle(.quiet) }
            case .found(let offer, let reply):
                found(offer, reply: reply)
            case .downloading(let received, let expected, let cancel):
                header(L("Загружаю обновление…"))
                if expected > 0 {
                    ProgressView(value: Double(min(received, expected)), total: Double(expected))
                    Text(L("%@ из %@", bytes(received), bytes(expected))).font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                buttons { Button(L("Отмена"), action: cancel).buttonStyle(.quiet) }
            case .extracting(let progress):
                header(L("Готовлю установку…"))
                if let progress { ProgressView(value: progress) } else { ProgressView().progressViewStyle(.linear) }
            case .readyToInstall(let reply):
                header(L("Обновление готово"), L("GhostlyAssistant закроется и откроется уже новой версией."))
                buttons {
                    Button(L("Позже")) { session.answer(reply, .dismiss) }.buttonStyle(.quiet)
                    Button(L("Установить и перезапустить")) { session.answer(reply, .install) }
                        .buttonStyle(.accent)
                        .keyboardShortcut(.defaultAction)
                }
            case .installing:
                header(L("Устанавливаю обновление…"))
                ProgressView().progressViewStyle(.linear)
            case .message(let title, let detail, let acknowledge):
                header(title, detail)
                buttons {
                    Button(L("Готово")) { session.finish(); acknowledge() }
                        .buttonStyle(.accent)
                        .keyboardShortcut(.defaultAction)
                }
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40) // clears the window buttons
        .padding(.bottom, 20)
        .frame(width: 520, alignment: .leading)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func found(_ offer: UpdateOffer, reply: @escaping (SPUUserUpdateChoice) -> Void) -> some View {
        header(L("Доступна новая версия GhostlyAssistant"),
               L("Версия %@ — у вас %@.", offer.version, AppUpdater.currentVersion)
                   + (offer.size > 0 ? " " + L("Размер %@.", bytes(offer.size)) : ""))
        ReleaseNotesView(notes: session.notes)
        HStack(spacing: 8) {
            Button(L("Пропустить эту версию")) { session.answer(reply, .skip) }.buttonStyle(.quiet)
            Spacer()
            Button(L("Напомнить позже")) { session.answer(reply, .dismiss) }.buttonStyle(.quiet)
            if offer.informationOnly {
                Button(L("Подробнее")) {
                    if let url = offer.infoURL { NSWorkspace.shared.open(url) }
                    session.answer(reply, .dismiss)
                }
                .buttonStyle(.accent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Установить")) { session.answer(reply, .install) }
                    .buttonStyle(.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func header(_ title: String, _ subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Spacer()
            content()
        }
    }

    private func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - Release notes

/// The "What's changed" text from the GitHub release, drawn natively: headings, bullet and numbered lists,
/// code blocks and inline Markdown. HTML notes (from older appcasts) go through AppKit's HTML reader.
private struct ReleaseNotesView: View {
    let notes: ReleaseNotes

    var body: some View {
        Group {
            switch notes {
            case .none:
                Text(L("Описание изменений не приложено.")).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .markdown(let text):
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                            block.view
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            case .html(let html):
                ScrollView {
                    Text(Self.attributed(html: html))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(height: 260)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
    }

    private static func attributed(html: String) -> AttributedString {
        guard let data = html.data(using: .utf8),
              let ns = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                     .characterEncoding: String.Encoding.utf8.rawValue],
                                               documentAttributes: nil)
        else { return AttributedString(html) }
        var plain = AttributedString(ns.string) // keep the text, drop the HTML fonts and colors so it follows the theme
        plain.font = .callout
        return plain
    }
}

/// One block of the release notes. An indented paragraph continues the list item one level up.
enum MarkdownBlock {
    case heading(String, level: Int)
    case item(marker: String, text: String, indent: Int)
    case paragraph(String, indent: Int)
    case code(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var code: [String]?
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code?.append(line); continue }
            guard !line.isEmpty else { continue }
            let indent = (raw.prefix { $0 == " " }.count + 1) / 3 // 2–3 spaces per nesting level
            if let m = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                blocks.append(.heading(String(m.2), level: m.1.count))
            } else if let m = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                blocks.append(.item(marker: "•", text: String(m.1), indent: indent))
            } else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) {
                blocks.append(.item(marker: "\(m.1).", text: String(m.2), indent: indent))
            } else if case .paragraph(let text, let lastIndent) = blocks.last, lastIndent == indent {
                blocks[blocks.count - 1] = .paragraph(text + " " + line, indent: indent) // a wrapped paragraph
            } else {
                blocks.append(.paragraph(line, indent: indent))
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        return blocks
    }

    @ViewBuilder var view: some View {
        switch self {
        case .heading(let text, let level):
            Text(Self.inline(text))
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .item(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
                Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(.leading, CGFloat(indent) * 18)
        case .paragraph(let text, let indent):
            Text(Self.inline(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, indent > 0 ? CGFloat(indent - 1) * 18 + 20 : 0) // lines up with the item's text
        case .code(let text):
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
