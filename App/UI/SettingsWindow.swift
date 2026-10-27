import AppKit
import SwiftUI

/// Settings in a plain window that is also excluded from screen capture.
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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Налаштування"
            w.sharingType = .none
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var key = ""

    static let zoomHint = "Щоб картку не було видно в трансляції: Zoom → Settings → Share Screen → Advanced → Screen capture mode → Advanced capture with window filtering. Якщо картку все одно видно — демонструйте окреме вікно, а не весь екран, або інший дисплей (картку тримайте на екрані ноутбука). Перевіряйте на пристрої іншого учасника. Сховати картку: ⌥⌘H."

    var body: some View {
        Form {
            Section("Ключ Claude API") {
                SecureField(model.hasAPIKey ? "Ключ збережено — введіть новий, щоб замінити" : "sk-ant-…", text: $key)
                Button("Зберегти") {
                    model.saveAPIKey(key)
                    key = ""
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Демонстрація екрана в Zoom") {
                Text(Self.zoomHint)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
