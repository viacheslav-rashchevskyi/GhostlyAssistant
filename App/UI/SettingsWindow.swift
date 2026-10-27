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
            w.title = "Настройки"
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

    static let zoomHint = "Чтобы карточку не было видно в трансляции: Zoom → Settings → Share Screen → Advanced → Screen capture mode → Advanced capture with window filtering. Если карточку всё равно видно — демонстрируйте отдельное окно, а не весь экран, или другой дисплей (карточку держите на экране ноутбука). Проверяйте на устройстве другого участника. Скрыть карточку: ⌥⌘H."

    var body: some View {
        Form {
            Section("Ключ Claude API") {
                SecureField(model.hasAPIKey ? "Ключ сохранён — введите новый, чтобы заменить" : "sk-ant-…", text: $key)
                Button("Сохранить") {
                    model.saveAPIKey(key)
                    key = ""
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Демонстрация экрана в Zoom") {
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
